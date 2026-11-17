# Implantação pela Oracle Cloud Console

## 1. Confira a cota e o custo

Em 17/11/2026, a [página oficial Always Free](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) apresenta **1.500 OCPU-h e 9.000 GB-h por mês** para Ampere A1, equivalentes a **2 OCPUs e 12 GB** no total. Uma VM com 2 OCPUs e 6 GB, ativa por 31 dias, consome 1.488 OCPU-h e 4.464 GB-h. Confira a cota somada a outros recursos A1 da sua conta na região principal.

| Recurso | Seleção |
| --- | --- |
| Região | Home region da tenancy |
| Shape | `VM.Standard.A1.Flex`, 2 OCPUs e 6 GB |
| Imagem | Canonical Ubuntu 24.04 LTS ARM64, elegível para Always Free |
| Armazenamento | Volume de boot padrão, cerca de 50 GB. Some todos os volumes de boot e bloco ao limite gratuito de 200 GB |
| Rede | VCN com sub-rede pública, Internet Gateway e IPv4 público efêmero na VM para saída |
| Acesso remoto | Tailscale Personal, plano de US$ 0 |

Na tela de criação, confirme a marcação **Always Free Eligible**, a disponibilidade e a estimativa coerente com o nível gratuito da conta. Se faltar capacidade, aguarde ou tente outro domínio de disponibilidade da mesma home region. O valor de R$ 0 depende da cota total, da elegibilidade dos recursos e da manutenção do plano gratuito. Confira a [tabela de preços da Oracle](https://www.oracle.com/cloud/price-list/), o [nível gratuito da Oracle](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm) e o [plano Personal do Tailscale](https://tailscale.com/pricing).

A Oracle pode recuperar instâncias gratuitas classificadas como ociosas. A documentação usa métricas de CPU, rede e, em A1, memória ao longo de sete dias. Baixa utilização é esperada neste projeto. Use o volume e os backups dentro da cota para recuperação e considere a possibilidade de uma interrupção ou de falta de capacidade para recriar a VM. [Critérios oficiais de ociosidade](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

## 2. Prepare a chave SSH

Em PowerShell no Windows, ou em um terminal com OpenSSH, gere uma chave no seu computador.

```powershell
ssh-keygen -t ed25519 -f "$HOME/.ssh/pokeidle_oci" -C "pokeidle-oci"
```

Escolha uma frase secreta. No Console use apenas o conteúdo de `pokeidle_oci.pub`. Guarde o arquivo privado `pokeidle_oci` no dispositivo de administração. [Chaves SSH compatíveis com OCI](https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/managingkeypairs.htm).

## 3. Prepare a rede e crie a instância

1. Na home region, abra **Networking → Virtual Cloud Networks**. Use uma VCN e uma sub-rede pública disponíveis ou crie uma VCN dedicada com uma sub-rede pública e um Internet Gateway. Ao criar manualmente, configure uma rota `0.0.0.0/0` para esse gateway e mantenha saída IPv4 stateful para a internet. Confira que a sub-rede utiliza essa tabela de rotas e a lista de segurança esperada.
2. Na lista de segurança da sub-rede ou num NSG associado, permita temporariamente entrada stateful **TCP 22** somente a partir do seu IPv4 público com máscara `/32`. Se a VCN for dedicada ao projeto, revise também a lista padrão e retire qualquer regra que permita SSH de qualquer origem. As permissões de listas e NSGs associados são cumulativas. Mantenha `5901/TCP`, `5902/TCP` e portas X11 sem entrada pública. Para o Tailscale, a conexão pode funcionar por relay usando a saída da VM.
3. Abra **Compute → Instances → Create instance**. Use o nome `pokeidle-cloud`. Em **Image and shape**, selecione Ubuntu 24.04 ARM64 e a shape Ampere A1 Flex. Informe 2 OCPUs e 6 GB. Em **Networking**, selecione sua sub-rede pública e um **IPv4 público atribuído na criação**. Em **Add SSH keys**, cole a chave pública. Mantenha o volume de boot padrão e o desempenho padrão, sem discos extras. Revise a configuração e crie só depois de confirmar a elegibilidade.
4. Aguarde o estado **Running** e anote o IPv4 público. Ao conectar pela primeira vez, confirme a identidade da VM antes de confiar na chave de host SSH. [Criação de instância](https://docs.oracle.com/pt-br/iaas/Content/Compute/Tasks/launchinginstance.htm) · [IPv4 efêmero](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/assign-public-ip-instance-launch.htm).

## 4. Envie os arquivos e instale

Extraia o ZIP em seu computador. No PowerShell ou terminal, entre na pasta que contém `pokeidle-cloud` e execute os comandos, substituindo `IP_PUBLICO` pelo IPv4 da instância.

```powershell
scp -i "$HOME/.ssh/pokeidle_oci" -r ./pokeidle-cloud ubuntu@IP_PUBLICO:~/
ssh -i "$HOME/.ssh/pokeidle_oci" ubuntu@IP_PUBLICO
```

Na VM, siga a [instalação do README](../README.md#instalação). Se o sistema de arquivos perder as permissões executáveis durante a extração, use `bash install.sh --check` e `sudo bash install.sh`.

## 5. Feche a administração pública

1. Entre na mesma tailnet no computador, confirme que o VNC funciona pelo IPv4 Tailscale e teste uma nova conexão SSH usando a mesma chave privada. Neste projeto o OpenSSH do Ubuntu continua autenticando o usuário `ubuntu`; o Tailscale fornece o caminho de rede.

   ```powershell
   ssh -i "$HOME/.ssh/pokeidle_oci" ubuntu@IP_TAILSCALE
   ```

2. Com a conexão privada validada, retire a regra de entrada pública TCP 22 no Console. Mantenha o IPv4 público efêmero e o Internet Gateway para que a VM continue chegando à internet. Confirme as regras TCP também no NSG, se houver. Guarde o procedimento de reabrir temporariamente o SSH só para seu IPv4 `/32` caso perca o acesso privado.
3. Mantenha apenas seus dispositivos confiáveis na tailnet e proteja a conta usada no Tailscale com MFA. Se usa uma tailnet compartilhada, restrinja as portas TCP 22, 5901 e 5902 da VM a seus dispositivos ou à sua identidade. As regras são aditivas, então retire também permissões mais amplas que concedam o mesmo acesso. Confira os detalhes no [controle de acesso do Tailscale](https://tailscale.com/docs/features/access-control). Use Serve privado nas portas do projeto.
4. No Android, teste o VNC pelo 4G/5G com o Tailscale ligado. Para confirmar a restrição, desligue o Tailscale no celular e confirme que o endereço privado fica inacessível e que as portas VNC no IPv4 público também recusam a conexão.
