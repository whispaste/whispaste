# WhisPaste

> WhisPaste es una aplicación de entrada por voz gratuita y con licencia MIT para Windows, Mac con Apple Silicon y Linux: pulsas un atajo de teclado, hablas y el texto aparece en el campo de texto activo. El reconocimiento de voz se ejecuta localmente en tu ordenador.

## Qué hace WhisPaste

- Pulsas un atajo global en cualquier aplicación, hablas y lo vuelves a pulsar (o lo mantienes pulsado mientras hablas).
- WhisPaste transcribe la grabación en tu ordenador y copia el texto al portapapeles. Con el pegado automático activado, lo inserta en el cursor de la aplicación activa, en casi cualquier app.
- Pensado para quienes escriben mucho en el escritorio: correos, mensajes, documentos, notas, prompts y comentarios de código.

## Reconocimiento de voz

- Dos motores locales: Whisper (whisper.cpp, 99 idiomas, varios tamaños de modelo) y Parakeet (unos 25 idiomas europeos, rápido incluso sin GPU).
- Tras una descarga única del modelo, el reconocimiento local funciona sin conexión.
- La GPU es opcional. La aceleración usa Metal en Apple Silicon y Vulkan en Windows y Linux; para NVIDIA hay un paquete CUDA opcional. Sin GPU, el reconocimiento se ejecuta en la CPU.
- Reconocimiento en la nube opcional a través de OpenAI o Deepgram con tu propia clave de API.

## Smart Mode (opcional, desactivado por defecto)

- Limpiar elimina muletillas y corrige la puntuación, Resumir acorta el texto y Traducir lo convierte al alemán, inglés, español, francés, portugués, mandarín o ruso.
- Funciona localmente (macOS y Windows; experimental en Linux) o a través de OpenAI con tu propia clave de API.

## En el día a día

- Historial local de transcripciones y notas rápidas aparte.
- Fragmentos: bloques de texto guardados que se insertan con un atajo o una palabra clave dicha en voz alta; los fragmentos interactivos rellenan una plantilla.
- Importación de archivos: transcribe archivos de audio existentes.

## Privacidad

- Con el reconocimiento local, el audio se queda en tu ordenador y se descarta tras la transcripción, salvo que actives su conservación.
- No hace falta ninguna cuenta.
- Las estadísticas de uso y los informes de errores no contienen audio, transcripciones ni historial y se pueden desactivar en Ajustes → Privacidad.
- Las funciones en la nube solo envían datos al proveedor elegido y solo cuando las usas.

## Plataformas y requisitos

- Windows 10 o posterior, macOS 12 Monterey o posterior en Apple Silicon (los Mac con Intel no son compatibles), Linux x64 (AppImage, .deb, tar.gz).
- Recomendado: al menos 8 GB de RAM y un procesador de 64 bits.
- Solo escritorio; no hay versión para iOS ni Android.

## Precio y licencia

- La aplicación completa es gratuita en GitHub bajo la licencia MIT.
- Las versiones de pago de Microsoft Store y Mac App Store ofrecen las mismas funciones principales con actualizaciones a través de la tienda.
- Sin suscripción. Los proveedores en la nube opcionales pueden cobrar por su uso.

## Enlaces

- [Sitio web](https://whispaste.de/es/)
- [Descarga](https://whispaste.de/es/download/)
- [Política de privacidad](https://whispaste.de/es/privacy/)
- [Registro de cambios](https://whispaste.de/es/changelog/)
- [Código fuente en GitHub](https://github.com/whispaste/whispaste)
