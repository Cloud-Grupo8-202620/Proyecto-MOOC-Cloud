package scanner

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/courses"
	"github.com/DiegoMunevar2007/Proyecto-1-Cloud.git/queue"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

type fakeStore struct {
	downloads int
	deleted   []string
	err       error
}

func (f *fakeStore) DownloadToFile(_, _, dest string) error {
	f.downloads++
	if f.err != nil {
		return f.err
	}
	return os.WriteFile(dest, []byte("contenido"), 0o600)
}

func (f *fakeStore) DeleteFile(_, key string) error {
	f.deleted = append(f.deleted, key)
	return nil
}

type fakeQueue struct {
	published []queue.TranscodePayload
	err       error
}

func (f *fakeQueue) EnqueueTranscode(_ context.Context, p queue.TranscodePayload, _ string) (string, error) {
	if f.err != nil {
		return "", f.err
	}
	f.published = append(f.published, p)
	return "id", nil
}

func TestPayloadIncompletoEsPermanente(t *testing.T) {
	s := &Service{}
	if err := s.Handle(context.Background(), queue.ScanPayload{}); !IsPermanent(err) {
		t.Fatalf("se esperaba error permanente, llegó %v", err)
	}
}

func TestErrorPermanenteSeReconoce(t *testing.T) {
	if !IsPermanent(Permanent(errors.New("x"))) || IsPermanent(errors.New("clamav caído")) {
		t.Fatal("clasificación de errores incorrecta")
	}
}

// newDB abre un esquema propio en PostgreSQL con solo la tabla de recursos.
// Se omite si no hay base de datos, igual que las demás pruebas de integración.
func newDB(t *testing.T) *gorm.DB {
	t.Helper()
	dsn := os.Getenv("POSTGRES_TEST_DSN")
	if dsn == "" {
		t.Skip("POSTGRES_TEST_DSN no está definido; se omite la prueba de integración")
	}
	admin, err := gorm.Open(postgres.Open(dsn), &gorm.Config{Logger: logger.Discard})
	if err != nil {
		t.Fatalf("conectar: %v", err)
	}
	schema := fmt.Sprintf("scanner_test_%d", time.Now().UnixNano())
	if err := admin.Exec("CREATE SCHEMA " + schema).Error; err != nil {
		t.Fatalf("crear esquema: %v", err)
	}
	t.Cleanup(func() { admin.Exec("DROP SCHEMA " + schema + " CASCADE") })
	db, err := gorm.Open(postgres.Open(dsn+" search_path="+schema), &gorm.Config{Logger: logger.Discard})
	if err != nil {
		t.Fatalf("conectar a esquema: %v", err)
	}
	sqlDB, _ := db.DB()
	sqlDB.SetMaxOpenConns(1)
	t.Cleanup(func() { _ = sqlDB.Close() })
	if err := db.AutoMigrate(&courses.Resource{}); err != nil {
		t.Fatalf("migrar: %v", err)
	}
	return db
}

func nuevoRecurso(t *testing.T, db *gorm.DB, typ string) courses.Resource {
	t.Helper()
	r := courses.Resource{UnitID: 1, StableID: "res-1", Type: typ, Title: "r", ObjectKey: "obj.mp4",
		MimeType: "video/mp4", ScanStatus: courses.ScanPending, ProcessingStatus: courses.ProcessingPending}
	if err := db.Create(&r).Error; err != nil {
		t.Fatalf("crear recurso: %v", err)
	}
	return r
}

func estado(t *testing.T, db *gorm.DB, id uint) courses.Resource {
	t.Helper()
	var r courses.Resource
	if err := db.First(&r, id).Error; err != nil {
		t.Fatalf("leer: %v", err)
	}
	return r
}

func limpio(string, string) (bool, string, error)   { return false, "", nil }
func infectado(string, string) (bool, string, error) { return true, "Eicar", nil }

func TestScanLimpioEncadenaTranscodeUnaVez(t *testing.T) {
	db := newDB(t)
	r := nuevoRecurso(t, db, courses.ResourceTypeVideo)
	store, q := &fakeStore{}, &fakeQueue{}
	s := &Service{DB: db, Store: store, Queue: q, ScanFile: limpio}
	p := queue.ScanPayload{ResourceID: r.ID, ObjectKey: r.ObjectKey, TranscodeKey: "transcode-res-1"}

	if err := s.Handle(context.Background(), p); err != nil {
		t.Fatalf("primera entrega: %v", err)
	}
	if got := estado(t, db, r.ID).ScanStatus; got != courses.ScanClean {
		t.Fatalf("scan_status = %s", got)
	}
	// Reentrega: no descarga ni vuelve a escanear; solo reencadena el
	// transcode, que el worker deduplica por el estado del recurso.
	if err := s.Handle(context.Background(), p); err != nil {
		t.Fatalf("reentrega: %v", err)
	}
	if store.downloads != 1 {
		t.Fatalf("descargas = %d, se esperaba 1", store.downloads)
	}
	if len(q.published) != 2 || q.published[0].IdempotencyKey != q.published[1].IdempotencyKey {
		t.Fatalf("transcodes = %+v", q.published)
	}
}

func TestScanInfectadoEliminaYNoReencadena(t *testing.T) {
	db := newDB(t)
	r := nuevoRecurso(t, db, courses.ResourceTypeVideo)
	store, q := &fakeStore{}, &fakeQueue{}
	s := &Service{DB: db, Store: store, Queue: q, ScanFile: infectado}
	p := queue.ScanPayload{ResourceID: r.ID, ObjectKey: r.ObjectKey}

	for i := 0; i < 2; i++ {
		if err := s.Handle(context.Background(), p); err != nil {
			t.Fatalf("entrega %d: %v", i, err)
		}
	}
	got := estado(t, db, r.ID)
	if got.ScanStatus != courses.ScanInfected || got.ProcessingStatus != courses.ProcessingFailed {
		t.Fatalf("estado = %+v", got)
	}
	if len(store.deleted) != 1 || len(q.published) != 0 || store.downloads != 1 {
		t.Fatalf("borrados=%v transcodes=%d descargas=%d", store.deleted, len(q.published), store.downloads)
	}
}

func TestClamavCaidoEsTransitorioYNoCambiaEstado(t *testing.T) {
	db := newDB(t)
	r := nuevoRecurso(t, db, courses.ResourceTypeVideo)
	s := &Service{DB: db, Store: &fakeStore{}, Queue: &fakeQueue{},
		ScanFile: func(string, string) (bool, string, error) { return false, "", errors.New("connection refused") }}
	err := s.Handle(context.Background(), queue.ScanPayload{ResourceID: r.ID, ObjectKey: r.ObjectKey})
	if err == nil || IsPermanent(err) {
		t.Fatalf("se esperaba error transitorio, llegó %v", err)
	}
	if got := estado(t, db, r.ID).ScanStatus; got != courses.ScanPending {
		t.Fatalf("fail-closed: scan_status = %s", got)
	}
}

func TestRecursoInexistenteEsPermanente(t *testing.T) {
	db := newDB(t)
	s := &Service{DB: db, Store: &fakeStore{}, Queue: &fakeQueue{}, ScanFile: limpio}
	err := s.Handle(context.Background(), queue.ScanPayload{ResourceID: 999, ObjectKey: "x"})
	if !IsPermanent(err) {
		t.Fatalf("se esperaba error permanente, llegó %v", err)
	}
}

func TestDocumentoLimpioNoPublicaTranscode(t *testing.T) {
	db := newDB(t)
	r := nuevoRecurso(t, db, courses.ResourceTypePDF)
	q := &fakeQueue{}
	s := &Service{DB: db, Store: &fakeStore{}, Queue: q, ScanFile: limpio}
	if err := s.Handle(context.Background(), queue.ScanPayload{ResourceID: r.ID, ObjectKey: r.ObjectKey}); err != nil {
		t.Fatal(err)
	}
	if len(q.published) != 0 {
		t.Fatalf("no debía publicar transcode: %+v", q.published)
	}
}

func TestMarkFailed(t *testing.T) {
	db := newDB(t)
	r := nuevoRecurso(t, db, courses.ResourceTypeVideo)
	if err := (&Service{DB: db}).MarkFailed(r.ID); err != nil {
		t.Fatal(err)
	}
	got := estado(t, db, r.ID)
	if got.ScanStatus != courses.ScanFailed || got.ProcessingStatus != courses.ProcessingFailed {
		t.Fatalf("estado = %+v", got)
	}
}
