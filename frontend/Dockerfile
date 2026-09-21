# --- build stage ---------------------------------------------------------
FROM node:25-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# --- run stage -------------------------------------------------------------
# This image is for local development / CI smoke-testing parity.
# Production hosting is S3 + CloudFront, not this container (see README).
FROM nginx:1.27-alpine AS run
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/ || exit 1
