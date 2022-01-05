FROM nginx:alpine AS build
RUN mkdir /usr/share/nginx/html/cpp && \
    curl -sL https://upload.cppreference.com/mwiki/images/1/16/html_book_20190607.tar.xz | tar xJ --strip-components 1 -C /usr/share/nginx/html/cpp

FROM nginx:alpine
COPY --from=build /usr/share/nginx/html/cpp /usr/share/nginx/html/cpp
