# Example: OpenClaw agent image
#
# Build: sudo clawvps build openclaw --example          (uses this file)
#        sudo clawvps build myagent                     (uses ./myagent.Dockerfile or ./Dockerfile)
#        sudo clawvps build myagent -f ./my.Dockerfile  (explicit path)
#
# Rules for claw-vps Dockerfiles:
#  - FROM must be claw-vps/base — the bootable foundation (systemd, sshd,
#    networking). Plain ubuntu images cannot boot as a VM.
#  - ENTRYPOINT/CMD/EXPOSE are ignored — the VM boots with systemd. Register
#    always-on services with: RUN systemctl enable <unit>
#  - Never bake secrets (API keys etc.) into the image — inject them over SSH
#    after the VM is created.
FROM claw-vps/base

RUN apt-get update \
 && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
 && apt-get install -y nodejs \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest

# Onboarding (one-time, interactive): after `clawvps create`, run
#   ssh root@<IP>  →  openclaw onboard --install-daemon
