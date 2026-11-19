# WhisPaste

> O WhisPaste é um aplicativo de ditado para Windows, Macs com Apple Silicon e Linux: você pressiona um atalho, fala e o texto aparece no campo em que você está escrevendo. O reconhecimento de voz roda localmente no seu computador, sem necessidade de conta. Tem código aberto sob a licença MIT e é gratuito no GitHub; as versões da Microsoft Store e da Mac App Store são uma compra única sem assinatura; comprar não desbloqueia nada.

## O que o WhisPaste faz

- Você segura um atalho global em qualquer aplicativo enquanto fala e solta para parar, ou toca uma vez para começar e de novo para parar.
- O WhisPaste transcreve a gravação no seu computador e copia o texto para a área de transferência. Com a colagem automática ativada, ele insere o texto no cursor do aplicativo ativo, em quase qualquer app.
- Feito para quem escreve muito no computador: e-mails, mensagens, documentos, notas, prompts e comentários de código.

## O que o WhisPaste traz além do básico

Local, sem conta e de uso gratuito é o ponto de partida. Além disso, o WhisPaste traz:

- Smart Mode com modos prontos: limpar, encurtar ou traduzir para um de sete idiomas antes de colar o texto. Para mudar um texto selecionado, diga o que deve ficar diferente.
- O Smart Mode roda com um modelo de texto local que o WhisPaste baixa para você quando você pede; não é preciso instalar software adicional (experimental no Linux). Como alternativa, use sua própria chave da OpenAI.
- Gravações, notas e blocos de texto em um só editor, com a mesma barra de ferramentas, os mesmos atalhos e salvamento automático.
- Um dicionário com substituições que sugere novas substituições a partir das suas correções.
- Histórico, notas, dicionário, blocos de texto e gravações guardadas ficam criptografados com a chave de dados própria do seu dispositivo.
- Disponível na Microsoft Store e na Mac App Store: no Windows, instala sem o aviso do SmartScreen e atualiza em segundo plano pela loja; no Mac, instalação e atualizações pela App Store. Compra única, sem assinatura; a compra financia o desenvolvimento.

## Reconhecimento de voz

- Dois motores locais: Whisper (whisper.cpp, 99 idiomas, vários tamanhos de modelo) e Parakeet (cerca de 25 idiomas europeus, rápido mesmo sem GPU).
- Depois de baixar o modelo uma vez, o reconhecimento local funciona offline.
- A GPU é opcional. A aceleração usa Metal no Apple Silicon e Vulkan no Windows e no Linux; para NVIDIA há um pacote CUDA opcional. Sem GPU, o reconhecimento roda na CPU.
- Reconhecimento na nuvem opcional via OpenAI ou Deepgram com sua própria chave de API.
- Em Macs com macOS 26 ou posterior, o reconhecimento de voz da Apple no dispositivo é uma terceira opção.

## Smart Mode (opcional, desativado por padrão)

- Limpar remove palavras de preenchimento e corrige a pontuação, Resumir encurta o texto e Traduzir o converte para alemão, inglês, espanhol, francês, português, mandarim ou russo.
- Roda localmente (macOS e Windows; experimental no Linux) ou via OpenAI com sua própria chave de API.
- Presets próprios com sua própria instrução (até 500 caracteres); um preset pode ser aplicado depois a uma gravação anterior e o original é mantido. Em vez da OpenAI, também funciona um servidor compatível próprio (por exemplo Ollama, LM Studio, llama.cpp ou KoboldCpp) no computador ou na rede local.

## No dia a dia

- Área local Gravações com busca, filtros, salvamento automático e histórico de versões, além de notas com títulos, imagens, listas de tarefas, modo de leitura e modo foco.
- Snippets: blocos de texto salvos, inseridos por atalho ou por uma palavra-gatilho falada; snippets interativos preenchem um modelo.
- Importação de arquivos: transcreva áudio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) e vídeo (MP4, MOV, MKV, WebM), até 1 GB e 6 horas. Arquivos de áudio também podem ser enviados pelo gerenciador de arquivos: com “Abrir com” no Mac, no Linux e na versão da Microsoft Store para Windows, ou com o botão direito com o instalador para Windows do site.
- Opcionalmente, o WhisPaste pausa músicas e vídeos no Windows e no Linux enquanto você dita, e “Enviar após colar” pressiona Enter depois de colar (segure Alt ao soltar o atalho; no Linux, só X11).
- «Igualar o volume automaticamente» (ativado por padrão) aumenta a fala baixa antes do reconhecimento sem amplificar silêncio ou ruído.
- Até cinco idiomas de reconhecimento favoritos, marcados com uma estrela, aparecem primeiro nos menus de idioma; um atalho alterna entre eles.
- O vocabulário guarda nomes e termos técnicos; substituições corrigem grafias recorrentes, e o WhisPaste sugere novas a partir das suas correções repetidas.
- Perfis definem idioma, modelo de voz, Smart Mode, microfone e saída para um app específico.
- Editar seleção (opcional, desativado por padrão): selecione um texto em um app compatível, pressione o atalho e diga o que mudar, por exemplo “mais curto” ou “traduzir”; o Smart Mode reescreve a seleção.
- Se uma transcrição falhar, o áudio é mantido por 24 horas por padrão, mesmo após uma falha do app, para você tentar de novo.
- Acessibilidade: configurações, notas e ferramentas do editor funcionam com teclado e leitor de tela; com o modo de toque você nunca precisa segurar uma tecla.

## Privacidade

- Com o reconhecimento local, o áudio fica no seu computador e é descartado após a transcrição, a menos que você ative a retenção de áudio.
- No Windows e na versão para macOS do GitHub, o WhisPaste não cola automaticamente em campos de senha; o texto fica na área de transferência.
- Transcrições, notas, vocabulário, snippets e áudio guardado ficam salvos com criptografia, com uma chave de dados no armazenamento de chaves do sistema (Keychain do macOS, proteção de dados do Windows, Secret Service do Linux). Você pode fazer backup da chave como código de recuperação ou arquivo.
- Não é preciso criar conta.
- Estatísticas de uso anônimas e relatórios de falhas vêm ativados por padrão. Não contêm áudio, transcrições nem histórico, e cada um pode ser desativado em Configurações → Privacidade.
- Os recursos na nuvem só enviam dados ao provedor escolhido e só quando você os usa.

## Plataformas e requisitos

- Windows 10 ou posterior, macOS 13 Ventura ou posterior no Apple Silicon (Macs com Intel não são compatíveis), Linux x64 (AppImage, .deb, tar.gz) no Ubuntu 26.04 ou mais recente com glibc 2.43; sistemas Linux mais antigos ficam na versão 1.4.2.
- No Linux, funciona com X11 e Wayland. No Wayland, o desktop define o atalho global (pelo portal de atalhos no GNOME e no KDE, ou com um atalho próprio que execute `whispaste --toggle`), e alguns extras, como teclas únicas, toque duplo e “Enviar após colar”, precisam de X11. A colagem automática no Linux exige uma permissão única (teclado uinput ou portal do desktop); sem ela, o texto fica na área de transferência.
- Recomendado: pelo menos 8 GB de RAM e um processador de 64 bits.
- Somente desktop; não há versão para iOS nem Android.

## Como obter o WhisPaste e quanto custa

- Gratuito no GitHub, o aplicativo completo sob a licença MIT: instalador para Windows (WhisPaste-Setup.exe) ou ZIP portátil, DMG para macOS, AppImage, .deb e tar.gz para Linux. Gerenciadores de pacotes: winget (`SilvioLindstedt.WhisPaste`) e Scoop no Windows, Homebrew no macOS. Você também pode compilá-lo a partir do código-fonte.
- Microsoft Store (Windows) e Mac App Store (macOS): compra única, sem assinatura. A loja mostra o preço atual.
- O que a versão da loja acrescenta: no Windows, a instalação sem o aviso do SmartScreen que o instalador não assinado do GitHub pode gerar, e atualizações automáticas pela Microsoft Store. No macOS, instalação e atualizações pela App Store. A compra financia o desenvolvimento.
- Comprar não desbloqueia nada; a versão gratuita continua completa, sem nada bloqueado ou limitado no tempo. As versões do GitHub para Windows e macOS procuram novas versões e só instalam uma atualização depois que você confirma; no Linux, o WhisPaste apenas avisa sobre uma nova versão e mostra o link, e você a instala manualmente.
- Onde as versões diferem: o pacote CUDA opcional para placas NVIDIA recentes só está disponível nas versões do GitHub (Windows e Linux), não na versão da Microsoft Store; a aceleração por GPU via Vulkan funciona em ambas. A versão da Mac App Store roda no sandbox de apps da Apple: não aprende com correções que você faz em outros apps, não detecta campos de senha, não tem a alternativa de colagem via AppleScript nem a ferramenta que repara as permissões do macOS; a versão do GitHub tem tudo isso. A Mac App Store ainda oferece uma versão anterior, então a importação de arquivos de áudio e vídeo chega lá com a próxima atualização da loja.
- Uma nova versão pode chegar à Mac App Store depois do GitHub, porque a Apple revisa cada atualização.
- Sem assinatura e sem conta. Se você escolher um provedor de nuvem (OpenAI ou Deepgram), ele cobra o uso diretamente pela sua própria chave de API.

## Em que o WhisPaste difere do ditado integrado

- A digitação por voz integrada ao Windows (Win+H) usa o reconhecimento de voz online da Microsoft e precisa de conexão com a internet. O WhisPaste reconhece a fala no seu computador e funciona offline depois de baixar o modelo uma vez.
- O ditado integrado ao macOS usa apenas o reconhecimento de voz da Apple. No WhisPaste você escolhe entre Whisper, Parakeet, o reconhecimento da Apple no dispositivo (macOS 26 ou posterior) ou um provedor de nuvem com sua própria chave.
- Muitos desktops Linux não trazem nenhum ditado. O WhisPaste leva seu ditado também ao Linux, com os limites do Wayland citados acima.
- O ditado integrado digita enquanto você fala. O WhisPaste insere o texto pronto quando você para, guarda-o na área Gravações com busca, aplica seu vocabulário e seus snippets, pode limpá-lo com o Smart Mode e também transcreve arquivos de áudio e vídeo.

## Links

- [Site](https://whispaste.de/pt/)
- [Download](https://whispaste.de/pt/download/)
- [Política de privacidade](https://whispaste.de/pt/privacy/)
- [Histórico de alterações](https://whispaste.de/pt/changelog/)
- [Código-fonte no GitHub](https://github.com/whispaste/whispaste)
- [Microsoft Store](https://apps.microsoft.com/detail/9p22jvkrq2v0)
- [Mac App Store](https://apps.apple.com/app/id6795319409)
- [Versão mais recente no GitHub](https://github.com/whispaste/whispaste/releases/latest)
