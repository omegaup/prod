FROM fluent/fluent-bit:1.8

ADD https://github.com/newrelic/newrelic-fluent-bit-output/releases/download/v1.12.1/out_newrelic-linux-amd64-1.12.1.so /fluent-bit/lib/
ADD plugins.conf /fluent-bit/etc/

CMD ["/fluent-bit/bin/fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.conf", "--plugin=/fluent-bit/lib/out_newrelic-linux-amd64-1.12.1.so"]
