FROM golang:1.17-alpine AS build
COPY . src
RUN cd src && go build -o /go/bin/grader-backup .

FROM alpine:3.15
COPY --from=build /go/bin/grader-backup /usr/bin
CMD ["/usr/bin/grader-backup"]
