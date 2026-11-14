# El build produce archivos estáticos, iguales en cualquier arquitectura: corre
# nativo en la máquina que construye ($BUILDPLATFORM) y solo la etapa final,
# nginx, es de la plataforma de destino.
FROM --platform=$BUILDPLATFORM node:24-alpine AS build
WORKDIR /app
RUN npm install -g --ignore-scripts pnpm@12.15.0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --ignore-scripts
COPY . .
RUN pnpm run build

FROM nginx:alpine
# El entrypoint oficial sustituye ${BACKEND_URL} en la plantilla y escribe
# /etc/nginx/conf.d/default.conf antes de arrancar nginx.
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
# Valor de desarrollo; Cloud Run lo sobrescribe con la URL real del backend.
ENV BACKEND_URL=http://backend:8080
EXPOSE 3000
