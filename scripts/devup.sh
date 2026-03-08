#!/bin/bash
# ~/bin/devcontainer-wrapper (or wherever you keep scripts)

case "$(uname)" in
  Darwin)
    export HOST_SSH_AUTH_SOCK="/run/host-services/ssh-auth.sock"
    ;;
  Linux)
    export HOST_SSH_AUTH_SOCK="$SSH_AUTH_SOCK"
    ;;
esac

exec devcontainer "$@"
