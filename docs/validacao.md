# Validação e recuperação

## Verificações locais

```bash
./tests/validate.sh
```

O script verifica a sintaxe Bash, as duas instâncias da unidade systemd, a seleção de sessões, a rejeição de VNC público e a supervisão da sessão. Os testes de supervisão usam processos simulados e um diretório temporário. A verificação da unidade usa caminhos de instalação adaptados ao ambiente de teste. Nenhum teste local cria recursos ou autentica no jogo.

A compatibilidade foi conferida nas referências de [Ubuntu ARM64 para Chromium](https://packages.ubuntu.com/noble/arm64/chromium-browser), [TigerVNC](https://packages.ubuntu.com/noble/arm64/tigervnc-standalone-server), [XFCE](https://packages.ubuntu.com/noble/arm64/xfce4-session) e [Tailscale para Linux](https://tailscale.com/docs/install/linux). O instalador recusa outras distribuições, versões e arquiteturas. O navegador real, a sessão gráfica, o acesso remoto e o PokéIdle aguardam validação numa VM ARM64.

## Aceitação na VM

1. Execute `uname -m`, `dpkg --print-architecture` e `snap list chromium`. Confirme `aarch64`, `arm64` e o Chromium instalado.
2. Rode `sudo pokeidle-doctor`. Confirme duas unidades ativas, dois processos Chromium, VNC em loopback e os encaminhamentos privados. Inspecione também `sudo tailscale serve status`.
3. Pelo PC e Android, conecte-se separadamente às duas portas. Confirme que cada uma abre o desktop esperado. Entre manualmente e confira se ambas as contas funcionam a partir da mesma VM.
4. Deixe o jogo em primeiro plano em cada desktop. Observe a atividade e desconecte os dois clientes VNC por 15 minutos. Reconecte e confira se houve progresso nas duas sessões. Faça uma verificação adicional depois de um período mais longo antes de depender da operação contínua.
5. Reinicie apenas a sessão 2 com `sudo pokeidle-recover 2`. Verifique que a primeira segue disponível e que a segunda reabre o perfil anterior. Confirme o estado do login e retome manualmente a atividade se necessário.
6. Em uma janela de manutenção, reinicie a VM. Confira os serviços, encaminhamentos e perfis depois do reboot. Monitore `free -h`, `df -h /` e a carga antes e depois do teste com duas sessões.

## Diagnóstico

| Sintoma | Verificação |
| --- | --- |
| VNC indisponível ou processo reiniciando | Use `sudo pokeidle-doctor 1` e `sudo journalctl -u pokeidle-session@1.service -n 100 --no-pager`. Se o log indicar senha ausente, configure com `sudo pokeidle-access password 1` e recupere a sessão. |
| VNC local ativo, celular sem acesso | Confirme que celular e VM estão conectados à mesma tailnet. Verifique o estado do Serve, a porta escolhida e a política de acesso. Se necessário, reative com `sudo pokeidle-access enable 1`. |
| APT não encontra os pacotes de XFCE ou TigerVNC | Verifique se o componente `universe` está habilitado nas fontes oficiais do Ubuntu 24.04 ARM64 e repita o instalador. |
| Erro do Snap ou tela sem Chromium | Confira `snap list chromium`, `snap connections chromium`, o journal e o socket D-Bus do usuário em `/run/user/UID/bus`. Verifique `loginctl show-user pokeidle-1 -p Linger`. Após corrigir a causa, use `sudo pokeidle-recover 1`. |
| Desktop ativo, jogo parado | Verifique mensagens do jogo, se ele pediu novo login, se a aba está em primeiro plano e se houve suspensão de aba. O diagnóstico verifica processos locais e o Serve. O progresso é confirmado dentro do jogo. |
| Bloqueio do IP ou conta pelo jogo | Verifique a mensagem e contate a equipe oficial. Respeite a decisão de moderação e os limites de rede. |
| Oracle recuperou a instância | Verifique na Console se ainda é possível iniciar a VM ou recuperar o volume. Se a capacidade estiver esgotada, aguarde uma forma Always Free na home region. |

O volume de boot guarda os perfis; um encerramento da instância com exclusão do volume remove esses dados. Se criar backup de volume, confirme a elegibilidade e a cota gratuita. Trate qualquer cópia do perfil ou volume como material privado, pois contém cookies e outros dados de sessão. Guarde as chaves SSH separadamente e faça o login manual no jogo e no Tailscale após recriar a VM, quando necessário.
