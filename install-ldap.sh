ytt -f ldap.yaml -f placeholders.yaml -v 'default_ldap_password=VMware1!' > openldap-one-OU.yaml

# Get openldap docker image, upload to harbor:
echo "Getting OpenLDAP image to harbor..."
# docker pull  quay.io/vdesikanvmware/openldap:latest
# docker login harbor.tanzu.io:8443 --username admin --password Harbor12345
# docker tag quay.io/vdesikanvmware/openldap:latest harbor.tanzu.io:8443/library/openldap
# docker push harbor.tanzu.io:8443/library/openldap

docker pull quay.io/vdesikanvmware/openldap:latest
docker login harbor.tanzu-e2e.com --username admin --password VMware1!
docker tag quay.io/vdesikanvmware/openldap:latest harbor.tanzu-e2e.com/library/openldap
docker push harbor.tanzu-e2e.com/library/openldap


# Utilize Shepherd Root CA to create SSL cert
echo "Creating OpenLDAP SSL cert..."
export TEST_DOMAIN=tanzu.io

cat > min_ext.cnf << EOF
[v3_ca]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ldap.${TEST_DOMAIN}
DNS.2 = ldap.openldap.svc.cluster.local
EOF

# Generate keypair
openssl genrsa -out ldap.key 4096

# Create Cert signing request
openssl req -sha512 -new -subj "/C=US/ST=California/L=Palo Alto/O=VMware, Inc./OU=IT/CN=ldap.tanzu.io" -key ldap.key -out ldap.csr

# Sign CSR with root CA from this testbed
openssl x509 -req -sha512 -days 3650 -extfile min_ext.cnf -extensions v3_req -CA ~/certs/ca.crt -CAkey ~/certs/ca.key -CAcreateserial -in ldap.csr -out ldap.crt

# See SANs: openssl x509 -text -noout -in ldap.crt

# Get certs in proper format and directory
openssl x509 -in ldap.crt -out ldap.pem
openssl rsa -in ldap.key > ldap-key.pem
# 2023-10-03 - Now specifying the full path so this script can be run from subfolders
openssl x509 -in ~/certs/ca.crt -out ./ca.pem
# NOTE: This ca.pem must also go into the rootCA key in values.yaml for the TMC SM deployment

# Create NS and secret for OpenLDAP cert
echo "Updating K8s environment..."
kubectl create ns openldap
kubectl label namespaces openldap pod-security.kubernetes.io/audit=privileged --overwrite=true
kubectl label namespaces openldap pod-security.kubernetes.io/audit-version=latest --overwrite=true
kubectl label namespaces openldap pod-security.kubernetes.io/enforce=privileged --overwrite=true
kubectl label namespaces openldap pod-security.kubernetes.io/enforce-version=latest --overwrite=true
kubectl label namespaces openldap pod-security.kubernetes.io/warn=privileged --overwrite=true
kubectl label namespaces openldap pod-security.kubernetes.io/warn-version=latest --overwrite=true
kubectl create secret generic -n openldap certs --from-file=ldap.pem --from-file=ldap-key.pem --from-file=ca.pem

# Create OpenLDAP deployment
kubectl apply -f openldap-one-OU.yaml

echo "Done deploying OpenLDAP in namespace 'openldap'"
