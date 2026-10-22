#!/usr/bin/env bash
# Installs the pinned toolchain. Safe to re-run: skips anything already at the right version.
set -euo pipefail

KUBECTL_VERSION="v1.31.1"
HELM_VERSION="v3.16.2"
TERRAFORM_VERSION="1.9.8"
YQ_VERSION="v4.44.3"
BIN="${HOME}/.local/bin"
mkdir -p "$BIN"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"; [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"; [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"

if [[ "$OS" == "darwin" ]]; then
  command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
  brew install kubectl helm hashicorp/tap/terraform awscli jq yq pre-commit
  echo "done (macOS via Homebrew)"; exit 0
fi

has() { command -v "$1" >/dev/null 2>&1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# kubectl (checksum verified)
if has kubectl && kubectl version --client 2>/dev/null | grep -q "$KUBECTL_VERSION"; then
  echo "kubectl ok"
else
  url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl"
  curl -fsSLo "$TMP/kubectl" "$url"
  echo "$(curl -fsSL "${url}.sha256")  $TMP/kubectl" | sha256sum -c -
  install -m 0755 "$TMP/kubectl" "$BIN/kubectl"
fi

# helm (checksum verified)
if has helm && helm version --short 2>/dev/null | grep -q "$HELM_VERSION"; then
  echo "helm ok"
else
  f="helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
  curl -fsSLo "$TMP/$f" "https://get.helm.sh/${f}"
  echo "$(curl -fsSL "https://get.helm.sh/${f}.sha256sum" | awk '{print $1}')  $TMP/$f" | sha256sum -c -
  tar -xzf "$TMP/$f" -C "$TMP" && install -m 0755 "$TMP/linux-${ARCH}/helm" "$BIN/helm"
fi

# terraform (checksum verified)
if has terraform && terraform version 2>/dev/null | head -1 | grep -q "$TERRAFORM_VERSION"; then
  echo "terraform ok"
else
  f="terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip"
  base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"
  curl -fsSLo "$TMP/$f" "$base/$f"
  (cd "$TMP" && curl -fsSL "$base/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep " $f\$" | sha256sum -c -)
  unzip -o -q "$TMP/$f" -d "$TMP" && install -m 0755 "$TMP/terraform" "$BIN/terraform"
fi

# yq
if has yq && yq --version 2>/dev/null | grep -q "$YQ_VERSION"; then
  echo "yq ok"
else
  curl -fsSLo "$TMP/yq" "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}"
  install -m 0755 "$TMP/yq" "$BIN/yq"
fi

# aws cli v2
if has aws && aws --version 2>&1 | grep -q "aws-cli/2"; then
  echo "aws ok"
else
  a="x86_64"; [[ "$ARCH" == "arm64" ]] && a="aarch64"
  curl -fsSLo "$TMP/awscli.zip" "https://awscli.amazonaws.com/awscli-exe-linux-${a}.zip"
  unzip -q "$TMP/awscli.zip" -d "$TMP" && "$TMP/aws/install" -i "$HOME/.local/aws-cli" -b "$BIN" --update
fi

# jq + pre-commit
has jq || sudo apt-get install -y jq
has pre-commit || pip install --user pre-commit

echo "Make sure $BIN is on your PATH, then run: make doctor"
