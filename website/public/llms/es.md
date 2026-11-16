# WhisPaste

> WhisPaste es una aplicación de entrada por voz gratuita y con licencia MIT para Windows, Mac con Apple Silicon y Linux: pulsas un atajo de teclado, hablas y el texto aparece en el campo de texto activo. El reconocimiento de voz se ejecuta localmente en tu ordenador.

## Qué hace WhisPaste

- Mantienes pulsado un atajo global en cualquier aplicación mientras hablas y lo sueltas para detener, o lo tocas una vez para empezar y otra para detener.
- WhisPaste transcribe la grabación en tu ordenador y copia el texto al portapapeles. Con el pegado automático activado, lo inserta en el cursor de la aplicación activa, en casi cualquier app.
- Pensado para quienes escriben mucho en el escritorio: correos, mensajes, documentos, notas, prompts y comentarios de código.

## Reconocimiento de voz

- Dos motores locales: Whisper (whisper.cpp, 99 idiomas, varios tamaños de modelo) y Parakeet (unos 25 idiomas europeos, rápido incluso sin GPU).
- Tras una descarga única del modelo, el reconocimiento local funciona sin conexión.
- La GPU es opcional. La aceleración usa Metal en Apple Silicon y Vulkan en Windows y Linux; para NVIDIA hay un paquete CUDA opcional. Sin GPU, el reconocimiento se ejecuta en la CPU.
- Reconocimiento en la nube opcional a través de OpenAI o Deepgram con tu propia clave de API.
- En Mac con macOS 26 o posterior, el reconocimiento de voz de Apple en el dispositivo es una tercera opción.

## Smart Mode (opcional, desactivado por defecto)

- Limpiar elimina muletillas y corrige la puntuación, Resumir acorta el texto y Traducir lo convierte al alemán, inglés, español, francés, portugués, mandarín o ruso.
- Funciona localmente (macOS y Windows; experimental en Linux) o a través de OpenAI con tu propia clave de API.
- Presets propios con tu propia instrucción (hasta 500 caracteres); un preset se puede aplicar más tarde a una grabación anterior y el original se conserva. En lugar de OpenAI también funciona un servidor compatible propio (por ejemplo LM Studio u Ollama) en tu ordenador o tu red local.

## En el día a día

- Área local Grabaciones con búsqueda, filtros, guardado automático e historial de versiones, además de notas con títulos, imágenes, listas de tareas, vista de lectura y modo concentración.
- Fragmentos: bloques de texto guardados que se insertan con un atajo o una palabra clave dicha en voz alta; los fragmentos interactivos rellenan una plantilla.
- Importación de archivos: transcribe audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) y vídeo (MP4, MOV, MKV, WebM), hasta 1 GB y 6 horas. Los archivos de audio también se envían desde el explorador de archivos: con «Abrir con» en Mac, en Linux y en la versión de Microsoft Store para Windows, o con clic derecho con el instalador para Windows de la web.
- Opcionalmente, WhisPaste pausa la música y los vídeos en Windows y Linux mientras dictas, y «Enviar tras pegar» pulsa Intro después de pegar (mantén Alt al soltar el atajo; en Linux solo X11).
- «Igualar el volumen automáticamente» (activado por defecto) sube la voz baja antes del reconocimiento sin amplificar el silencio ni el ruido.
- Hasta cinco idiomas de reconocimiento favoritos, marcados con una estrella, aparecen primero en los menús de idioma; un atajo cambia entre ellos.
- El vocabulario guarda nombres y términos especializados; los reemplazos corrigen errores recurrentes y WhisPaste propone nuevos a partir de tus correcciones repetidas.
- Los perfiles fijan idioma, modelo de voz, Smart Mode, micrófono y salida para una app concreta.
- Si una transcripción falla, el audio se conserva 24 horas por defecto, incluso tras un cierre inesperado, para que puedas reintentarlo.
- Accesibilidad: ajustes, notas y herramientas del editor funcionan con teclado y lector de pantalla; con el modo de toque nunca tienes que mantener pulsada una tecla.

## Privacidad

- Con el reconocimiento local, el audio se queda en tu ordenador y se descarta tras la transcripción, salvo que actives su conservación.
- En macOS y Windows, WhisPaste no pega automáticamente en campos de contraseña; el texto queda en el portapapeles.
- Las transcripciones, las notas, el vocabulario, los snippets y el audio conservado se guardan cifrados con una clave de datos en el almacén de claves del sistema (llavero de macOS, protección de datos de Windows, Secret Service de Linux). Puedes hacer una copia de la clave como código de recuperación o archivo.
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
