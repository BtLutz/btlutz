FROM openjdk:11.0.16-jre-slim
LABEL maintainer=deck
WORKDIR /app
COPY libs libs/
COPY resources resources/
COPY classes classes/
ENTRYPOINT ["java", "-cp", "/app/resources:/app/classes:/app/libs/*", "com.thelonelygecko.website.WebsiteApplication"]
EXPOSE 8080
