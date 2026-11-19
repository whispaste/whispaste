# WhisPaste

> WhisPaste es una aplicación de dictado para Windows, Mac con Apple Silicon y Linux: pulsas un atajo de teclado, hablas y el texto aparece en el campo en el que estás escribiendo. El reconocimiento de voz se ejecuta localmente en tu ordenador y no necesitas ninguna cuenta. Es de código abierto con licencia MIT y gratuita en GitHub; las versiones de Microsoft Store y Mac App Store son una compra única sin suscripción; comprar no desbloquea nada.

## Qué hace WhisPaste

- Mantienes pulsado un atajo global en cualquier aplicación mientras hablas y lo sueltas para detener, o lo tocas una vez para empezar y otra para detener.
- WhisPaste transcribe la grabación en tu ordenador y copia el texto al portapapeles. Con el pegado automático activado, lo inserta en el cursor de la aplicación activa, en casi cualquier app.
- Pensado para quienes escriben mucho en el escritorio: correos, mensajes, documentos, notas, prompts y comentarios de código.

## Lo que WhisPaste añade a lo básico

Local, sin cuenta y de uso gratuito es el punto de partida. Además, WhisPaste ofrece:

- Smart Mode con modos listos para usar: limpiar, acortar o traducir a uno de siete idiomas antes de pegar el texto. Para cambiar un texto seleccionado, di qué debe cambiar.
- Smart Mode funciona con un modelo de texto local que WhisPaste descarga por ti cuando lo pides; no hace falta instalar software adicional (experimental en Linux). Como alternativa, usa tu propia clave de OpenAI.
- Grabaciones, notas y bloques de texto en un mismo editor, con la misma barra de herramientas, los mismos atajos y guardado automático.
- Un diccionario con reemplazos que sugiere reemplazos nuevos a partir de tus correcciones.
- El historial, las notas, el diccionario, los bloques de texto y las grabaciones guardadas se almacenan cifrados con la clave de datos propia de tu dispositivo.
- Disponible en Microsoft Store y en Mac App Store: en Windows se instala sin la advertencia de SmartScreen y se actualiza en segundo plano a través de la tienda; en Mac, la instalación y las actualizaciones pasan por App Store. Compra única, sin suscripción; la compra financia el desarrollo.

## Reconocimiento de voz

- Dos motores locales: Whisper (whisper.cpp, 99 idiomas, varios tamaños de modelo) y Parakeet (unos 25 idiomas europeos, rápido incluso sin GPU).
- Tras una descarga única del modelo, el reconocimiento local funciona sin conexión.
- La GPU es opcional. La aceleración usa Metal en Apple Silicon y Vulkan en Windows y Linux; para NVIDIA hay un paquete CUDA opcional. Sin GPU, el reconocimiento se ejecuta en la CPU.
- Reconocimiento en la nube opcional a través de OpenAI o Deepgram con tu propia clave de API.
- En Mac con macOS 26 o posterior, el reconocimiento de voz de Apple en el dispositivo es una tercera opción.

## Smart Mode (opcional, desactivado por defecto)

- Limpiar elimina muletillas y corrige la puntuación, Resumir acorta el texto y Traducir lo convierte al alemán, inglés, español, francés, portugués, mandarín o ruso.
- Funciona localmente (macOS y Windows; experimental en Linux) o a través de OpenAI con tu propia clave de API.
- Presets propios con tu propia instrucción (hasta 500 caracteres); un preset se puede aplicar más tarde a una grabación anterior y el original se conserva. En lugar de OpenAI también funciona un servidor compatible propio (por ejemplo Ollama, LM Studio, llama.cpp o KoboldCpp) en tu ordenador o tu red local.

## En el día a día

- Área local Grabaciones con búsqueda, filtros, guardado automático e historial de versiones, además de notas con títulos, imágenes, listas de tareas, vista de lectura y modo concentración.
- Fragmentos: bloques de texto guardados que se insertan con un atajo o una palabra clave dicha en voz alta; los fragmentos interactivos rellenan una plantilla.
- Importación de archivos: transcribe audio (WAV, MP3, FLAC, M4A, AAC, Ogg, Opus) y vídeo (MP4, MOV, MKV, WebM), hasta 1 GB y 6 horas. Los archivos de audio también se envían desde el explorador de archivos: con «Abrir con» en Mac, en Linux y en la versión de Microsoft Store para Windows, o con clic derecho con el instalador para Windows de la web.
- Opcionalmente, WhisPaste pausa la música y los vídeos en Windows y Linux mientras dictas, y «Enviar tras pegar» pulsa Intro después de pegar (mantén Alt al soltar el atajo; en Linux solo X11).
- «Igualar el volumen automáticamente» (activado por defecto) sube la voz baja antes del reconocimiento sin amplificar el silencio ni el ruido.
- Hasta cinco idiomas de reconocimiento favoritos, marcados con una estrella, aparecen primero en los menús de idioma; un atajo cambia entre ellos.
- El vocabulario guarda nombres y términos especializados; los reemplazos corrigen errores recurrentes y WhisPaste propone nuevos a partir de tus correcciones repetidas.
- Los perfiles fijan idioma, modelo de voz, Smart Mode, micrófono y salida para una app concreta.
- Editar selección (opcional, desactivado por defecto): selecciona texto en una app compatible, pulsa su atajo y di qué quieres cambiar, por ejemplo «más corto» o «traducir»; Smart Mode reescribe la selección.
- Si una transcripción falla, el audio se conserva 24 horas por defecto, incluso tras un cierre inesperado, para que puedas reintentarlo.
- Accesibilidad: ajustes, notas y herramientas del editor funcionan con teclado y lector de pantalla; con el modo de toque nunca tienes que mantener pulsada una tecla.

## Privacidad

- Con el reconocimiento local, el audio se queda en tu ordenador y se descarta tras la transcripción, salvo que actives su conservación.
- En Windows y en la versión para macOS de GitHub, WhisPaste no pega automáticamente en campos de contraseña; el texto queda en el portapapeles.
- Las transcripciones, las notas, el vocabulario, los snippets y el audio conservado se guardan cifrados con una clave de datos en el almacén de claves del sistema (llavero de macOS, protección de datos de Windows, Secret Service de Linux). Puedes hacer una copia de la clave como código de recuperación o archivo.
- No hace falta ninguna cuenta.
- Las estadísticas de uso anónimas y los informes de errores están activados por defecto. No contienen audio, transcripciones ni historial, y cada uno se puede desactivar en Ajustes → Privacidad.
- Las funciones en la nube solo envían datos al proveedor elegido y solo cuando las usas.

## Plataformas y requisitos

- Windows 10 o posterior, macOS 13 Ventura o posterior en Apple Silicon (los Mac con Intel no son compatibles), Linux x64 (AppImage, .deb, tar.gz) en Ubuntu 26.04 o posterior con glibc 2.43; los sistemas Linux más antiguos se quedan en la versión 1.4.2.
- En Linux funciona con X11 y Wayland. En Wayland, el escritorio asigna el atajo global (mediante el portal de atajos en GNOME y KDE, o con un atajo propio que ejecute `whispaste --toggle`), y algunos extras, como las teclas sueltas, el doble toque y «Enviar tras pegar», necesitan X11. El pegado automático en Linux requiere un permiso único (teclado uinput o portal del escritorio); sin él, el texto queda en el portapapeles.
- Recomendado: al menos 8 GB de RAM y un procesador de 64 bits.
- Solo escritorio; no hay versión para iOS ni Android.

## Cómo conseguir WhisPaste y cuánto cuesta

- Gratis en GitHub, la aplicación completa con licencia MIT: instalador para Windows (WhisPaste-Setup.exe) o ZIP portátil, DMG para macOS, AppImage, .deb y tar.gz para Linux. Gestores de paquetes: winget (`SilvioLindstedt.WhisPaste`) y Scoop en Windows, Homebrew en macOS. También puedes compilarla tú mismo desde el código fuente.
- Microsoft Store (Windows) y Mac App Store (macOS): compra única, sin suscripción. La tienda muestra el precio actual.
- Qué añade la versión de la tienda: en Windows, la instalación sin el aviso de SmartScreen que puede mostrar el instalador sin firmar de GitHub, y actualizaciones automáticas a través de Microsoft Store. En macOS, instalación y actualizaciones a través de la App Store. La compra financia el desarrollo.
- Comprar no desbloquea nada; la versión gratuita sigue completa, sin nada bloqueado ni limitado en el tiempo. Las versiones de GitHub para Windows y macOS buscan nuevas versiones e instalan una actualización solo después de que la confirmes; en Linux, WhisPaste solo avisa de una nueva versión y la enlaza, y la instalas tú a mano.
- En qué se diferencian las versiones: el paquete CUDA opcional para tarjetas NVIDIA recientes solo está disponible en las versiones de GitHub (Windows y Linux), no en la de Microsoft Store; la aceleración por GPU mediante Vulkan funciona en ambas. La versión de la Mac App Store se ejecuta en el sandbox de apps de Apple: no puede aprender de las correcciones que haces en otras apps, no detecta campos de contraseña, no tiene la alternativa de pegado mediante AppleScript ni la herramienta que repara los permisos de macOS; la versión de GitHub sí tiene todo esto. La Mac App Store ofrece por ahora una versión anterior, así que la importación de archivos de audio y vídeo llegará allí con la próxima actualización de la tienda.
- Una nueva versión puede llegar a la Mac App Store más tarde que a GitHub, porque Apple revisa cada actualización.
- Sin suscripción y sin cuenta. Si eliges un proveedor en la nube (OpenAI o Deepgram), te cobra su uso directamente a través de tu propia clave de API.

## En qué se diferencia WhisPaste del dictado integrado

- La escritura por voz integrada en Windows (Win+H) usa el reconocimiento de voz en línea de Microsoft y necesita conexión a internet. WhisPaste reconoce la voz en tu ordenador y funciona sin conexión tras una descarga única del modelo.
- El dictado integrado en macOS solo usa el reconocimiento de voz de Apple. En WhisPaste eliges entre Whisper, Parakeet, el reconocimiento de Apple en el dispositivo (macOS 26 o posterior) o un proveedor en la nube con tu propia clave.
- Muchos escritorios Linux no incluyen ningún dictado. WhisPaste lleva su dictado también a Linux, con los límites de Wayland indicados arriba.
- El dictado integrado escribe mientras hablas. WhisPaste inserta el texto terminado cuando paras, lo guarda en el área Grabaciones con búsqueda, aplica tu vocabulario y tus fragmentos, puede limpiarlo con Smart Mode y también transcribe archivos de audio y vídeo.

## Enlaces

- [Sitio web](https://whispaste.de/es/)
- [Descarga](https://whispaste.de/es/download/)
- [Política de privacidad](https://whispaste.de/es/privacy/)
- [Registro de cambios](https://whispaste.de/es/changelog/)
- [Código fuente en GitHub](https://github.com/whispaste/whispaste)
- [Microsoft Store](https://apps.microsoft.com/detail/9p22jvkrq2v0)
- [Mac App Store](https://apps.apple.com/app/id6795319409)
- [Última versión en GitHub](https://github.com/whispaste/whispaste/releases/latest)
