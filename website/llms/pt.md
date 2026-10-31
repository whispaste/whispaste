# WhisPaste

> O WhisPaste é um aplicativo de entrada por voz gratuito, com licença MIT, para Windows, Macs com Apple Silicon e Linux: você pressiona um atalho, fala e o texto aparece no campo de texto ativo. O reconhecimento de voz roda localmente no seu computador.

## O que o WhisPaste faz

- Você pressiona um atalho global em qualquer aplicativo, fala e pressiona de novo (ou mantém pressionado enquanto fala).
- O WhisPaste transcreve a gravação no seu computador e copia o texto para a área de transferência. Com a colagem automática ativada, ele insere o texto no cursor do aplicativo ativo, em quase qualquer app.
- Feito para quem escreve muito no computador: e-mails, mensagens, documentos, notas, prompts e comentários de código.

## Reconhecimento de voz

- Dois motores locais: Whisper (whisper.cpp, 99 idiomas, vários tamanhos de modelo) e Parakeet (cerca de 25 idiomas europeus, rápido mesmo sem GPU).
- Depois de baixar o modelo uma vez, o reconhecimento local funciona offline.
- A GPU é opcional. A aceleração usa Metal no Apple Silicon e Vulkan no Windows e no Linux; para NVIDIA há um pacote CUDA opcional. Sem GPU, o reconhecimento roda na CPU.
- Reconhecimento na nuvem opcional via OpenAI ou Deepgram com sua própria chave de API.

## Smart Mode (opcional, desativado por padrão)

- Limpar remove palavras de preenchimento e corrige a pontuação, Resumir encurta o texto e Traduzir o converte para alemão, inglês, espanhol, francês, português, mandarim ou russo.
- Roda localmente (macOS e Windows; experimental no Linux) ou via OpenAI com sua própria chave de API.

## No dia a dia

- Histórico local de transcrições e notas rápidas separadas.
- Snippets: blocos de texto salvos, inseridos por atalho ou por uma palavra-gatilho falada; snippets interativos preenchem um modelo.
- Importação de arquivos: transcreva arquivos de áudio existentes.

## Privacidade

- Com o reconhecimento local, o áudio fica no seu computador e é descartado após a transcrição, a menos que você ative a retenção de áudio.
- Não é preciso criar conta.
- Estatísticas de uso e relatórios de falhas não contêm áudio, transcrições nem histórico e podem ser desativados em Configurações → Privacidade.
- Os recursos na nuvem só enviam dados ao provedor escolhido e só quando você os usa.

## Plataformas e requisitos

- Windows 10 ou posterior, macOS 12 Monterey ou posterior no Apple Silicon (Macs com Intel não são compatíveis), Linux x64 (AppImage, .deb, tar.gz).
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
