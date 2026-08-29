group "default" {
  targets = ["local"]
}
variable "DOCKER_REGISTRY" {
  default = "local"
}
variable "DOCKER_REPOSITORY" {
  default = "iam"
}
variable "DOCKER_TAG" {
  default = "latest"
}

target "_common" {
  context = "."
  dockerfile = "Dockerfile"
  platforms = ["linux/amd64"]
  networks = ["host"]
  buildkit = true
}

group "local" {
  targets = ["build-local"]
}

group "build-local" {
  targets = ["build-local-proxy", "build-local-kc"]
}

group "registry" {
  targets = ["registry-proxy", "registry-kc"]
}

target "build-local-proxy" {
  inherits = ["_common"]
  target = "proxy-runtime"
  tags = [
    "local/${DOCKER_REPOSITORY}/proxy:${DOCKER_TAG}",
  ]
  output = [
    "type=docker,name=local/${DOCKER_REPOSITORY}/proxy:${DOCKER_TAG}"
  ]
}

target "build-local-kc" {
  inherits = ["_common"]
  target = "kc-runtime"
  tags = [
    "local/${DOCKER_REPOSITORY}/kc:${DOCKER_TAG}",
  ]
  output = [
    "type=docker,name=local/${DOCKER_REPOSITORY}/kc:${DOCKER_TAG}"
  ]
}

target "registry-proxy" {
  inherits = ["_common"]
  pull = true
  progress = ["plain", "tty"]
  target = "proxy-runtime"
  tags = [
    "${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/proxy:${DOCKER_TAG}",
  ]
  output = [
    "type=image,name=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/proxy:${DOCKER_TAG},push=true",
  ]
}

target "registry-kc" {
  inherits = ["_common"]
  pull = true
  progress = ["plain", "tty"]
  target = "kc-runtime"
  tags = [
    "${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/kc:${DOCKER_TAG}",
  ]
  output = [
    "type=image,name=${DOCKER_REGISTRY}/${DOCKER_REPOSITORY}/kc:${DOCKER_TAG},push=true",
  ]
}
