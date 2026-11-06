<div align="center">

# LogiSync

**Aperte o Easy-Switch no teclado Logitech e o mouse vai junto.**
Funciona entre Windows, Linux, macOS, Android e iOS, inclusive com teclados e mouses que o
*Enhanced Easy-Switch* oficial da Logitech não suporta.

[English](README.md) · [Português](README.pt-BR.md) · [Como funciona](docs/PROTOCOL.md)

</div>

---

Teclados e mouses Logitech com **Easy-Switch** pareiam com até 3 aparelhos, mas cada um troca de
canal sozinho. O teclado tem tecla para isso; o mouse tem um botão embaixo. O LogiSync faz o mouse
seguir o teclado:

```
 teclado: Easy-Switch 1 -> 2              teclado: Easy-Switch 2 -> 1
 PC percebe que o teclado saiu            celular percebe que o teclado saiu
 PC manda o mouse para o canal 2   ───►   celular manda o mouse para o canal 1  ───► volta ao PC
```

Não troca driver e não grava firmware. Um agente pequeno roda em cada aparelho. Quando o teclado
sai, ele manda ao mouse o mesmo comando HID++ `CHANGE_HOST` que o software da Logitech usa.
Detalhes da engenharia reversa: [docs/PROTOCOL.md](docs/PROTOCOL.md).

**Bônus no Android:** copia o layout de teclado exato do Windows para o celular, para cada tecla
digitar a mesma coisa nos dois (ex.: ABNT2 num teclado com gravação americana, `;` → `ç`).

## Situação

| Plataforma | Mouse segue o teclado | Testado em |
|---|---|---|
| Windows 10/11 | ✅ | Windows 11 + K950 + MX Anywhere 3 |
| Android 12+ | ✅ + layouts de teclado | Galaxy S25 Ultra, Android 17, inclusive no Samsung DeX |
| Linux (BlueZ) | 🧪 experimental | ainda não testado em hardware |
| macOS | 🧪 experimental | ainda não testado em hardware |
| iOS / iPadOS | 🧪 código experimental | ainda não compilado (precisa de Xcode e conta de desenvolvedor) |

## Passo a passo

> Antes, pareie o teclado **e** o mouse no mesmo número de canal em cada aparelho
> (ex.: PC = canal 1 nos dois, celular = canal 2 nos dois).

Depois instale o LogiSync em **cada** aparelho e configure *"quando o teclado sair daqui, mandar o
mouse para o canal N"*: no PC, canal 2; no celular, canal 1.

### Windows

Precisa do [Python 3.10+](https://www.python.org/downloads/).

```powershell
git clone https://github.com/Murilesco/logisync
cd logisync\desktop
powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Keyboard "K950" -Mouse "MX Anywhere" -Channel 2
```

Ele instala as dependências, copia o agente para `%LOCALAPPDATA%\LogiSync` e cria uma tarefa que
roda escondida no logon. Para remover: `install-windows.ps1 -Uninstall`.

### Android

1. Baixe o `LogiSync.apk` na [última versão](https://github.com/Murilesco/logisync/releases/latest)
   e instale (permita "instalar apps desconhecidos").
2. Abra o **LogiSync**, permita Bluetooth e notificações e aceite *ignorar otimização de bateria*.
3. Preencha os nomes do teclado e do mouse e o canal (ex.: `1`) e toque em **Salvar**.
   **Testar: mandar o mouse agora** deve mover o mouse na hora.
4. *(opcional)* Com o teclado conectado ao celular, toque em **Escolher layout do teclado físico**
   → seu teclado → cada teclado virtual → **Português (Brasil ABNT2) - igual ao Windows**.

### Linux e macOS

```bash
git clone https://github.com/Murilesco/logisync
cd logisync/desktop
./install-linux.sh     # ou ./install-macos.sh
```

Configuração e solução de problemas: veja o [README em inglês](README.md#configuration-desktop).

## Aviso

Projeto independente, sem relação com a Logitech. "Logitech", "Logi", "Easy-Switch", "MX" e os
nomes dos produtos são marcas da Logitech. Licença [MIT](LICENSE).
