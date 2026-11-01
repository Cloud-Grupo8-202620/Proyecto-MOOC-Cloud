# El build produce archivos estáticos, iguales en cualquier arquitectura: corre
# nativo en la máquina que construye ($BUILDPLATFORM) y solo la etapa final,
# nginx, es de la plataforma de destino. Desde un Mac ARM no se emula nada.
FROM --platform=$BUILDPLATFORM node:24-alpine AS build
WORKDIR /app
# node:lts dejó de incluir corepack y el build de la imagen fallaba con
# "/bin/sh: corepack: not found". Se fija Node 24 (el mismo de CI) y pnpm por
# versión exacta, la de package.json, en vez de depender de la imagen móvil.
RUN npm install -g pnpm@12.15.0
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY . .
RUN pnpm run build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 3000
