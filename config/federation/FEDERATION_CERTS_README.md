# Federation certificate notes
# See docs/FEDERATION.md for the full certificate exchange procedure.
#
# To federate two TAK servers, each must trust the other's CA.
# Exchange ca.pem files and import into each server's fed-truststore.jks:
#
#   keytool -importcert \
#       -file remote-ca.pem \
#       -keystore tak/certs/files/fed-truststore.jks \
#       -alias "remote-tak-server-ca"
#       -storepass atakatak
#
# Place remote CA .pem files here for documentation purposes.
# DO NOT commit private keys or .jks/.p12 files.
