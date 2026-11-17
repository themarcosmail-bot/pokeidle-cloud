# PokéIdle Cloud

Duas sessões gráficas persistentes em uma VM Ubuntu ARM64 da Oracle Cloud. A VM executa o jogo. O Android e o PC acessam a área de trabalho via Tailscale e podem se desconectar sem encerrá-la.

| Sessão | Usuário Linux | Display X11 | Porta privada | Perfil Chromium |
| --- | --- | --- | --- | --- |
| 1 | `pokeidle-1` | `:71` | `5901/TCP` | `/home/pokeidle-1/snap/chromium/common/pokeidle-profile` |
| 2 | `pokeidle-2` | `:72` | `5902/TCP` | `/home/pokeidle-2/snap/chromium/common/pokeidle-profile` |

Cada usuário tem seu próprio XFCE, display TigerVNC e perfil do Chromium. O navegador sai diretamente para a internet pelo IP da VM. O Tailscale Serve encaminha somente o acesso remoto aos serviços VNC que escutam em loopback.

## Instalação

1. Siga o [guia da Oracle Cloud Console](docs/oracle-cloud.md) para criar uma **VM.Standard.A1.Flex**, com **2 OCPUs, 6 GB de RAM**, Ubuntu Server 24.04 ARM64 e volume padrão de aproximadamente 50 GB. Confira a elegibilidade e a cota remanescente antes de criar.
2. Copie a pasta para a VM e execute estes comandos em um terminal SSH interativo.

   ```bash
   cd ~/pokeidle-cloud
   ./install.sh --check
   sudo ./install.sh
   sudo pokeidle-access password 1
   sudo pokeidle-access password 2
   sudo systemctl enable --now pokeidle-session@1.service pokeidle-session@2.service
   sudo tailscale up --hostname=pokeidle-cloud
   ```

3. Abra o link de login do Tailscale que aparece no terminal e autorize a VM na sua tailnet. No terminal, execute os comandos abaixo. Se o encaminhamento indicar que o VNC ainda está iniciando, aguarde a inicialização e repita o primeiro comando.

   ```bash
   sudo pokeidle-access enable
   sudo pokeidle-doctor
   ```

4. Instale o Tailscale no [Android](https://tailscale.com/download/android) e no [Windows](https://tailscale.com/download/windows) e entre na mesma tailnet. No Android, use um cliente VNC compatível com **VNC Authentication**, como AVNC. No PC, use o TigerVNC Viewer. Configure o mesmo IPv4 privado da VM nas duas conexões, com as portas `5901` e `5902`. Se o TigerVNC Viewer pedir um endereço em um único campo, use `IP_TAILSCALE::5901` ou `IP_TAILSCALE::5902`. Se o cliente oferecer uma lista de tipos de segurança, selecione `VncAuth` dentro da tailnet. A criptografia do tráfego entre os dispositivos é fornecida pelo Tailscale.
5. Entre manualmente em uma conta do jogo em cada desktop. Deixe a aba do jogo aberta e ativa na janela de cada Chromium. Feche somente o cliente VNC para se desconectar. Depois do teste de continuidade, você pode desligar o PC pessoal.

Para ativar primeiro uma sessão, inicie apenas `pokeidle-session@1.service` no passo 2 e use `sudo pokeidle-access enable 1` e `sudo pokeidle-doctor 1` no passo 3. Faça o mesmo para a sessão 2 quando for usá-la.

## Continuidade e regras do jogo

- O [PokéIdle](https://pokeidle.io/) informa que a atividade depende de uma aba aberta e que não há modo offline. As duas áreas de trabalho mantêm uma janela de jogo visível em cada display enquanto a VM está ligada, mesmo sem um cliente VNC conectado. Abas ocultas ou janelas minimizadas podem ter temporizadores reduzidos pelo Chromium. [Documentação do Chromium sobre temporizadores em segundo plano](https://developer.chrome.com/blog/timer-throttling-in-chrome-88).
- Um reboot recria o desktop e abre o Chromium com o perfil em disco. Cookies podem sobreviver, conforme as políticas e validade da sessão do jogo. Um login ou a retomada da caçada pode exigir ação manual.
- Os [termos do jogo, seção 5](https://pokeidle.io/terms), consultados em 17/11/2026, limitam a quatro contas por pessoa, considerando todos os dispositivos e redes. Também limitam a quatro contas criadas e quatro conectadas simultaneamente por rede. As sessões deste projeto usam a mesma rede de saída. Use duas contas dentro desses limites.
- Os termos descrevem verificações de IP e navegador e a possibilidade de bloqueio de uma rede. A disponibilidade do jogo para o IP de datacenter atribuído à sua VM só pode ser verificada depois da implantação. Se houver bloqueio ou dúvida sobre a rede, consulte o suporte em `support@pokeidle.io` ou via Discord oficial. Os scripts supervisionam apenas processos do Linux e do navegador.

## Operação

| Ação | Comando na VM |
| --- | --- |
| Verificar as duas sessões, Tailscale e recursos | `sudo pokeidle-doctor` |
| Verificar somente a primeira | `sudo pokeidle-doctor 1` |
| Recuperar a segunda, mantendo seu perfil | `sudo pokeidle-recover 2` |
| Recuperar ambas | `sudo pokeidle-recover all` |
| Ver os logs da primeira | `sudo journalctl -u pokeidle-session@1.service -n 100 --no-pager` |
| Remover o acesso remoto, mantendo os desktops ativos | `sudo pokeidle-access disable` |
| Pausar a segunda até uma ação manual | `sudo systemctl disable --now pokeidle-session@2.service` |

O systemd tenta reiniciar o desktop se o servidor X11 ou o XFCE encerrar. O instalador aplica um limite de partidas para falhas repetidas. O Chromium tem tentativas próprias de recuperação em caso de crash, com um intervalo de 15 segundos. Ao fechar normalmente o Chromium, o XFCE permanece aberto. Use `pokeidle-recover` para reabrir a sessão, se precisar. Todos os comandos de recuperação funcionam somente na VM.

## Arquivos

- `install.sh` verifica a plataforma, instala os pacotes e prepara os usuários e serviços. Uma reexecução preserva os perfis e senhas existentes.
- `scripts/` contém a inicialização de cada desktop, configuração de acesso, diagnóstico e recuperação.
- `systemd/` contém o serviço supervisionado por sessão.
- [Guia Oracle Cloud Console](docs/oracle-cloud.md) cobre cotas, rede e implantação.
- [Validação e recuperação](docs/validacao.md) cobre os testes locais e os testes de aceitação após a implantação.
