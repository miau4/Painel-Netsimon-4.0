# CHANGELOG — Correções e melhorias solicitadas (02/07/2026)

## 1. Causa raiz do bug "User X already exists" (Xray morrendo em loop)

**Diagnóstico confirmado:** múltiplos scripts (`adduser.sh`, `addtest.sh`,
`xray.sh`, `atlas.sh`) escreviam direto no `clients[]` do
`config.json` via `jq`, cada um por conta própria, **sem checar
duplicidade e sem lock entre processos concorrentes**.

O gatilho exato: em `adduser.sh` e `addtest.sh` a ordem de escrita era
**primeiro injeta no Xray, depois grava no `usuarios.db`**. O
`atlas_sync_users` roda via cron a cada 60s (+ no boot, via
`boot_check.sh`). Se esse cron disparasse exatamente nessa janela — o
usuário já injetado no Xray, mas ainda não gravado no
`usuarios.db` — o ramo "usuário novo" do `atlas_sync_users` não
encontrava o login no `usuarios.db` local e injetava o **mesmo email
de novo** no `clients[]`. Duplicata → Xray recusa subir (`exit 23`,
"User X already exists").

**Correção estrutural (não só o sintoma):** criado `xray_lib.sh`, uma
lib compartilhada com `xray_add_client_safe()` que:
- usa `flock` (serializa qualquer escrita concorrente vinda de
  qualquer script — painel, cron do Atlas, limiter, etc.);
- **sempre** checa se o email já existe antes de dar append;
- retorna `0` (adicionado), `2` (já existia — não duplicou) ou `1`
  (falha), pra cada chamador tratar o caso corretamente.

Todos os pontos de escrita foram migrados pra usar essa função:
`adduser.sh`, `addtest.sh`, `xray.sh` (criar usuário), `atlas.sh`
(as duas rotas do sync), `unblock.sh` e `limit.sh` (kick/reconexão).

**Fechando o ciclo para a próxima instalação:** `install.sh` agora
baixa `xray_lib.sh` junto com os outros módulos e, logo após subir o
Xray com config zerada, faz um **resync único e serializado** de
qualquer `usuarios.db` pré-existente (isso acontece em reinstalação,
já que o `touch` do passo 5 não apaga o arquivo se ele já existir).
Isso evita depender do cron do Atlas pra repovoar o Xray depois de
reinstalar — que era exatamente a corrida que causava o bug.

## 2. Xray Manager (menu 19) — novas opções

- **[3] Ver Lista de Usuários (UUID completo):** nova tela dentro do
  Xray Manager mostrando cada usuário com o UUID inteiro (na tela
  inicial, opção 04, o UUID continua cortado propositalmente pra
  caber na tabela — a versão completa agora vive aqui).
- **[8] Desinstalar Xray Completamente:** remove binário, serviço
  systemd, config, certificados SSL e o watchdog do cron. Confirmação
  é **só apertar ENTER** (Ctrl+C cancela) — sem precisar digitar
  "sim" ou senha.
- **Portas corrigidas:** `draw_status()` usava `.inbounds[0].port`,
  que é sempre a porta 2000 (API interna do Xray, não a porta de
  tráfego real) — por isso a porta mostrada nunca batia com a
  configurada de fato. Agora ignora o inbound `dokodemo-door` e
  mostra todas as portas de tráfego real, cruzando com o que está
  de fato em LISTEN (`ss -tlnp`) pra refletir o estado real do
  servidor.
- **Criar Usuário Xray em sincronia total:** antes, criar usuário
  pelo Xray Manager só mexia no `config.json` — não gravava no
  `usuarios.db` (sumia da lista principal do painel), não tinha
  validade controlada pelo limiter, e não existia no Atlas
  (DragonCore). Agora segue exatamente o mesmo fluxo de
  `adduser.sh`: cria usuário Linux, grava no `usuarios.db`, injeta no
  Xray com lock/dedup e sincroniza com o Atlas.

## 3. Cor das opções — azul turquesa `#00FFEF`

Aplicada a todas as opções numeradas/selecionáveis de todos os menus
interativos do painel: `menu.sh` (principal), `xray.sh` (Xray
Manager), `atlas.sh` (Atlas Manager), `websocket.sh` (WebSocket
Manager), `slowdns-server.sh` (SlowDNS Manager) e `checkuser.sh`
(CheckUser API). Cor implementada como true color ANSI
(`\033[38;2;0;255;239m`), variável `$T` em cada arquivo. Bordas,
títulos e indicadores de status (ON/OFF, cores de erro/sucesso)
foram mantidos como estavam — só as opções em si mudaram de cor.

## Arquivos alterados/criados

| Arquivo | O que mudou |
|---|---|
| `xray_lib.sh` | **NOVO** — lib compartilhada (dedup + lock) |
| `xray.sh` | Reescrito: porta corrigida, +2 opções, sync, cor |
| `adduser.sh` | Usa `xray_add_client_safe` |
| `addtest.sh` | Usa `xray_add_client_safe` |
| `atlas.sh` | Usa lib nos 2 pontos de sync + cor no `atlas_menu` |
| `limit.sh` | `kick_xray_uuid` usa lib (remove+add com lock) |
| `unblock.sh` | Usa `xray_add_client_safe`, elimina race TOCTOU |
| `install.sh` | Baixa `xray_lib.sh` + resync pós-instalação |
| `menu.sh` | Cor turquesa nas 22 opções |
| `websocket.sh` | Cor turquesa nas opções |
| `slowdns-server.sh` | Cor turquesa nas opções |
| `checkuser.sh` | Cor turquesa nas opções |

## Recomendação de teste no servidor

```bash
# 1. Validar sintaxe de tudo antes de subir pro GitHub
for f in *.sh; do bash -n "$f" || echo "FALHA: $f"; done

# 2. No servidor, depois de puxar do GitHub:
bash /etc/painel/xray.sh     # testar menu 19 isoladamente
bash /etc/painel/menu.sh     # testar menu principal
```
