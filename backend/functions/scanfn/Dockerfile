# Solo desarrollo local (docker compose): en Google Cloud la función se
# despliega desde código fuente con Terraform, sin imagen propia.
FROM --platform=$BUILDPLATFORM golang:alpine AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /scanfn ./functions/scanfn/cmd/local

FROM alpine:latest
WORKDIR /app
RUN apk add --no-cache ca-certificates
COPY --from=builder /scanfn /app/scanfn
RUN addgroup -S app && adduser -S -G app app
USER app
EXPOSE 8080
CMD ["./scanfn"]
