#!/usr/bin/env bash
# vm-virtualbox.sh — cria e opera a VM de bancada do riOS (Eee PC 1015BX)
#
# uso:
#   vm-virtualbox.sh vazio                 cria a VM com disco vazio (instalar Debian)
#   vm-virtualbox.sh imagem <arq.img>      cria a VM a partir da imagem do projeto
#   vm-virtualbox.sh iso <debian.iso>      anexa uma ISO e bota por ela
#   vm-virtualbox.sh boot disco|dvd        muda a ordem de boot
#   vm-virtualbox.sh iniciar [gui|headless]
#   vm-virtualbox.sh parar                 desliga pelo botão ACPI
#   vm-virtualbox.sh snapshot <nome>       tira um snapshot
#   vm-virtualbox.sh restaurar <nome>      volta a um snapshot
#   vm-virtualbox.sh info                  mostra a configuração
#   vm-virtualbox.sh remover               apaga a VM e o disco
#
# variáveis: VM (nome), RAM, CPUS, CAP, VDI_DIR, DISK_MB
set -euo pipefail

VM="${VM:-rios}"
RAM="${RAM:-1536}"
CPUS="${CPUS:-2}"
CAP="${CAP:-70}"
VDI_DIR="${VDI_DIR:-$HOME/VMs}"
DISK_MB="${DISK_MB:-40960}"
VDI="$VDI_DIR/$VM.vdi"

erro() { echo "erro: $*" >&2; exit 1; }

need_vbox() {
  command -v VBoxManage >/dev/null 2>&1 || erro "VBoxManage não encontrado (instale o VirtualBox)"
}

iface_padrao() {
  ip -o -4 route show default 2>/dev/null | awk '{print $5; exit}'
}

existe() {
  VBoxManage list vms 2>/dev/null | grep -q "\"$VM\""
}

criar_base() {
  need_vbox
  if existe; then
    erro "a VM '$VM' já existe; rode '$0 remover' antes de recriar"
  fi

  local bridge
  bridge="$(iface_padrao || true)"

  VBoxManage createvm --name "$VM" --ostype Debian_64 --register

  VBoxManage modifyvm "$VM" \
    --cpus "$CPUS" --memory "$RAM" --vram 128 --ioapic on \
    --firmware efi --graphicscontroller vmsvga --accelerate3d off \
    --cpuexecutioncap "$CAP" --nested-hw-virt off --paravirtprovider none \
    --mouse usbtablet --keyboard ps2 \
    --audio-enabled off --usb-ehci on --usb-ohci on \
    --boot1 disk --boot2 dvd --boot3 none --boot4 none

  if [ -n "$bridge" ]; then
    VBoxManage modifyvm "$VM" \
      --nic1 bridged --bridgeadapter1 "$bridge" --nictype1 82540EM
  else
    VBoxManage modifyvm "$VM" --nic1 nat --natpf1 "ssh,tcp,,2222,,22"
  fi

  VBoxManage storagectl "$VM" --name SATA --add sata \
    --controller IntelAhci --portcount 2 --hostiocache off
  VBoxManage storagectl "$VM" --name IDE --add ide

  mkdir -p "$VDI_DIR"
  echo "VM '$VM' criada (RAM ${RAM} MB, ${CPUS} vCPU, limite ${CAP}%)"
}

cmd_vazio() {
  criar_base
  VBoxManage createmedium disk --filename "$VDI" \
    --size "$DISK_MB" --variant Standard
  VBoxManage storageattach "$VM" --storagectl SATA --port 0 --device 0 \
    --type hdd --medium "$VDI"
  echo "disco vazio de ${DISK_MB} MB em $VDI"
  echo "próximo passo: $0 iso <debian-13-netinst.iso>"
}

cmd_imagem() {
  local img="${1:-}"
  [ -n "$img" ] || erro "uso: $0 imagem <arquivo.img>"
  [ -f "$img" ] || erro "imagem não encontrada: $img"
  criar_base
  echo "convertendo $img em VDI (o .img não é alterado)…"
  VBoxManage convertfromraw "$img" "$VDI" --format VDI
  VBoxManage storageattach "$VM" --storagectl SATA --port 0 --device 0 \
    --type hdd --medium "$VDI"
  VBoxManage snapshot "$VM" take "imagem-limpa" >/dev/null
  echo "pronto: $0 iniciar"
}

cmd_iso() {
  local iso="${1:-}"
  [ -n "$iso" ] || erro "uso: $0 iso <arquivo.iso>"
  [ -f "$iso" ] || erro "ISO não encontrada: $iso"
  VBoxManage storageattach "$VM" --storagectl IDE --port 1 --device 0 \
    --type dvddrive --medium "$iso"
  VBoxManage modifyvm "$VM" --boot1 dvd --boot2 disk
  echo "ISO anexada; boot pela unidade de DVD"
}

cmd_boot() {
  case "${1:-}" in
    disco) VBoxManage modifyvm "$VM" --boot1 disk --boot2 dvd ;;
    dvd)   VBoxManage modifyvm "$VM" --boot1 dvd --boot2 disk ;;
    *)     erro "uso: $0 boot disco|dvd" ;;
  esac
  echo "ordem de boot: ${1}"
}

cmd_iniciar() {
  need_vbox
  VBoxManage startvm "$VM" --type "${1:-gui}"
}

cmd_parar() {
  VBoxManage controlvm "$VM" acpipowerbutton
}

cmd_snapshot() {
  VBoxManage snapshot "$VM" take "${1:?uso: $0 snapshot <nome>}"
}

cmd_restaurar() {
  VBoxManage snapshot "$VM" restore "${1:?uso: $0 restaurar <nome>}"
}

cmd_info() {
  VBoxManage showvminfo "$VM" | sed -n '1,45p'
}

cmd_remover() {
  VBoxManage unregistervm "$VM" --delete
  echo "VM '$VM' e disco removidos"
}

case "${1:-}" in
  vazio)     shift; cmd_vazio "$@" ;;
  imagem)    shift; cmd_imagem "$@" ;;
  iso)       shift; cmd_iso "$@" ;;
  boot)      shift; cmd_boot "$@" ;;
  iniciar)   shift; cmd_iniciar "$@" ;;
  parar)     shift; cmd_parar ;;
  snapshot)  shift; cmd_snapshot "$@" ;;
  restaurar) shift; cmd_restaurar "$@" ;;
  info)      shift; cmd_info ;;
  remover)   shift; cmd_remover ;;
  *)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
