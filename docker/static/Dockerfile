FROM nginx:alpine AS build
RUN mkdir -p \
        /usr/share/nginx/html/docs/cpp/en \
        /usr/share/nginx/html/docs/java/en \
        /usr/share/nginx/html/docs/pas/en \
        /usr/share/nginx/html/docs/assets \
        && \
    curl -sL https://upload.cppreference.com/mwiki/images/1/16/html_book_20190607.tar.xz | \
        tar xJ --strip-components 1 -C /usr/share/nginx/html/docs/cpp && \
    curl -sL ftp://ftp.hu.freepascal.org/pub/fpc/dist/3.2.2/docs/doc-html.tar.gz | \
        tar xz --strip-components 1 -C /usr/share/nginx/html/docs/pas/en && \
      mv /usr/share/nginx/html/docs/pas/en/fpctoc.html /usr/share/nginx/html/docs/pas/en/index.html && \
   curl -sL https://download.oracle.com/otn_software/java/jdk/17.0.1+12/2a2082e5a09d4267845be086888add4f/jdk-17.0.1_doc-all.zip --output /tmp/jdk.zip && \
      unzip -q -d /tmp/ /tmp/jdk.zip && \
      mv /tmp/docs/* /usr/share/nginx/html/docs/java/en/ && \
      rm -rf /tmp/jdk.zip /tmp/docs && \
   curl -sL https://lobishomen.files.wordpress.com/2011/01/libropre3.pdf --output /usr/share/nginx/html/docs/assets/libroluisvargas.pdf

FROM nginx:alpine
COPY --from=build /usr/share/nginx/html /usr/share/nginx/html
