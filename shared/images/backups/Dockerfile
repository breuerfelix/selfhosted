FROM registry.k8s.io/kubectl:v1.37.3@sha256:82f06779a0dcd86225ffdb96c005418b9716093a39907a5ecf686d7a22e6b788 AS kubectl
FROM restic/restic:0.20.0@sha256:93999df80d4ac6cb148e82d2ef1fe6a81996f17ff535e772723538211b31555a

COPY --from=kubectl /bin/kubectl /usr/local/bin/kubectl
