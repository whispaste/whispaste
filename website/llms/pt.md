# WhisPaste

> O WhisPaste é um aplicativo de entrada por voz gratuito, com licença MIT, para Windows, Macs com Apple Silicon e Linux: você pressiona um atalho, fala e o texto aparece no campo de texto ativo. O reconhecimento de voz roda localmente no seu computador.

## O que o WhisPaste faz

- Você segura um atalho global em qualquer aplicativo enquanto fala e solta para parar, ou toca uma vez para começar e de novo para parar.
- O WhisPaste transcreve a gravação no seu computador e copia o texto para a área de transferência. Com a colagem automática ativada, ele insere o texto no cursor do aplicativo ativo, em quase qualquer app.
- Feito para quem escreve muito no computador: e-mails, mensagens, documentos, notas, prompts e comentários de código.

## Reconhecimento de voz

- Dois motores locais: Whisper (whisper.cpp, 99 idiomas, vários tamanhos de modelo) e Parakeet (cerca de 25 idiomas europeus, rápido mesmo sem GPU).
- Depois de baixar o modelo uma vez, o reconhecimento local funciona offline.
- A GPU é opcional. A aceleração usa Metal no Apple Silicon e Vulkan no Windows e no Linux; para NVIDIA há um pacote CUDA opcional. Sem GPU, o reconhecimento roda na CPU.
- Reconhecimento na nuvem opcional via OpenAI ou Deepgram com sua própria chave de API.
- Em Macs com macOS 26 ou posterior, o reconhecimento de voz da Apple no dispositivo é uma terceira opção.

## Smart Mode (opcional, desativado por padrão)

- Limpar remove palavras de preenchimento e corrige a pontuação, Resumir encurta o texto e Traduzir o converte para alemão, inglês, espanhol, francês, português, mandarim ou russo.
- Roda localmente (macOS e Windows; experimental no Linux) ou via OpenAI com sua própria chave de API.
- Presets próprios com sua própria instrução (até 500 caracteres); um preset pode ser aplicado depois a uma gravação anterior e o original é mantido. Em vez da OpenAI, também funciona um servidor compatível próprio (por exemplo LM Studio ou Ollama) no computador ou na rede local.

## No dia a dia

- Área local Gravações com busca, filtros, salvamento automático e histórico de versões, além de notas com títulos, imagens, listas de tarefas, modo de leitura e modo foco.
- Snippets: blocos de texto salvos, inseridos por atalho ou por uma palavra-gatilho falada; snippets interativos preenchem um modelo.
- Importação de arquivos: transcreva áudio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) e vídeo (MP4, MOV, MKV, WebM), até 1 GB e 6 horas. Arquivos de áudio também podem ser enviados pelo gerenciador de arquivos: com “Abrir com” no Mac, no Linux e na versão da Microsoft Store para Windows, ou com o botão direito com o instalador para Windows do site.
- Opcionalmente, o WhisPaste pausa músicas e vídeos no Windows e no Linux enquanto você dita, e “Enviar após colar” pressiona Enter depois de colar (segure Alt ao soltar o atalho; no Linux, só X11).
- «Igualar o volume automaticamente» (ativado por padrão) aumenta a fala baixa antes do reconhecimento sem amplificar silêncio ou ruído.
- Até cinco idiomas de reconhecimento favoritos, marcados com uma estrela, aparecem primeiro nos menus de idioma; um atalho alterna entre eles.
- O vocabulário guarda nomes e termos técnicos; substituições corrigem grafias recorrentes, e o WhisPaste sugere novas a partir das suas correções repetidas.
- Perfis definem idioma, modelo de voz, Smart Mode, microfone e saída para um app específico.
- Se uma transcrição falhar, o áudio é mantido por 24 horas por padrão, mesmo após uma falha do app, para você tentar de novo.
- Acessibilidade: configurações, notas e ferramentas do editor funcionam com teclado e leitor de tela; com o modo de toque você nunca precisa segurar uma tecla.

## Privacidade

- Com o reconhecimento local, o áudio fica no seu computador e é descartado após a transcrição, a menos que você ative a retenção de áudio.
- No macOS e no Windows, o WhisPaste não cola automaticamente em campos de senha; o texto fica na área de transferência.
- Transcrições, notas, vocabulário, snippets e áudio guardado ficam salvos com criptografia, com uma chave de dados no armazenamento de chaves do sistema (Keychain do macOS, proteção de dados do Windows, Secret Service do Linux). Você pode fazer backup da chave como código de recuperação ou arquivo.
- Não é preciso criar conta.
- Estatísticas de uso e relatórios de falhas não contêm áudio, transcrições nem histórico e podem ser desativados em Configurações → Privacidade.
- Os recursos na nuvem só enviam dados ao provedor escolhido e só quando você os usa.

## Plataformas e requisitos

- Windows 10 ou posterior, macOS 13 Ventura ou posterior no Apple Silicon (Macs com Intel não são compatíveis), Linux x64 (AppImage, .deb, tar.gz) no Ubuntu 26.04 ou mais recente com glibc 2.43; sistemas Linux mais antigos ficam na versão 1.4.2.
- Recomendado: pelo menos 8 GB de RAM e um processador de 64 bits.
- Somente desktop; não há versão para iOS nem Android.

## Preço e licença

- O aplicativo completo é gratuito no GitHub sob a licença MIT.
- As versões pagas na Microsoft Store e na Mac App Store oferecem os mesmos recursos principais, com atualizações pela loja.
- Sem assinatura. Provedores de nuvem opcionais podem cobrar pelo uso.

## Links

- [Site](https://whispaste.de/pt/)
- [Download](https://whispaste.de/pt/download/)
- [Política de privacidade](https://whispaste.de/pt/privacy/)
- [Histórico de alterações](https://whispaste.de/pt/changelog/)
- [Código-fonte no GitHub](https://github.com/whispaste/whispaste)
