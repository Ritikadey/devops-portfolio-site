FROM public.ecr.aws/lambda/nodejs:26

COPY package*.json ./
RUN npm ci --omit=dev

COPY src/ ./src/

CMD ["src/handler.handler"]
