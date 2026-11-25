/// The model catalog that ships with the app (#1513). The single source of
/// every model download: the registries (`sttModels`, `parakeetModelFiles`,
/// `parakeetGgufFiles`, `smartModeModel`) read their entries from here.
///
/// Sizes, hashes and sources are the pins from before the catalog, taken over
/// unchanged, so installed models stay valid without a new download. Every
/// source is a public host at a fixed revision; WhisPaste hosts no model
/// files. `tool/model_sources.json` mirrors the files for the live source
/// guard (`tool/check_model_sources.dart`, sync test
/// `test/services/model_sources_manifest_test.dart`).
///
/// Pin history:
/// - Whisper: one commit of ggerganov/whisper.cpp (OW-P18). The LFS SHA-256
///   at that commit equals the value below (checked 2026-10-19 via the HF
///   API).
/// - Parakeet (sherpa-onnx): one commit of
///   csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8, LFS hashes from the
///   tree API (checked 2026-10-19). `tokens.txt` is no LFS file and was hashed
///   from the download; its size is the redirect target's, not the 307's.
/// - Parakeet GGUF: one revision of ggml-org/parakeet-GGUF; the f16 file was
///   also reproduced locally from the NeMo checkpoint, byte for byte.
/// - Gemma: unsloth/gemma-4-E2B-it-GGUF, LFS metadata.
///
/// Memory values are guide values (resident model), see [ModelRequirements].
library;

import '../config/whisper_languages.dart';
import 'model_catalog.dart';

/// IDs of the catalog entries the app code refers to.
abstract final class CatalogIds {
  static const whisperSmall = 'whisper-small';
  static const whisperMedium = 'whisper-medium';
  static const whisperLargeV3Turbo = 'whisper-large-v3-turbo';
  static const parakeet = 'parakeet-tdt-0.6b-v3';
  static const parakeetGgufQ8 = 'parakeet-tdt-0.6b-v3-gguf-q8_0';
  static const parakeetGgufF16 = 'parakeet-tdt-0.6b-v3-gguf-f16';
  static const gemma4E2b = 'gemma-4-E2B-it-Q4_K_M';
}

/// The oldest version whose engines load exactly these files. A catalog
/// loaded later can name newer versions for models this one cannot run.
const String _minAppVersion = '1.5.2';

const String _whisperBase =
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1';

const String _parakeetOnnxBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/2bda32ec70b097a55adaa07d9a7173915b43cc78';

/// Pinned revision of `ggml-org/parakeet-GGUF`.
const String parakeetGgufRevision = '35156454d1a39de06863303dd209fd2bed6ee079';

const String _parakeetGgufBase =
    'https://huggingface.co/ggml-org/parakeet-GGUF/resolve/$parakeetGgufRevision';

const String _gemmaBase =
    'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/0314792d7f1f7e229411f620751375812bb9faf2';

/// Context window WhisPaste opens the Smart Mode model with.
const int kSmartModeContextLength = 2048;

/// ISO 639-1 codes for the 25 European languages `parakeet-tdt-0.6b-v3`
/// supports, per the NVIDIA model card (huggingface.co/nvidia/parakeet-tdt-0.6b-v3,
/// verified 2026-07-28).
const Set<String> parakeetSupportedLanguages = {
  'bg', // Bulgarian
  'hr', // Croatian
  'cs', // Czech
  'da', // Danish
  'nl', // Dutch
  'en', // English
  'et', // Estonian
  'fi', // Finnish
  'fr', // French
  'de', // German
  'el', // Greek
  'hu', // Hungarian
  'it', // Italian
  'lv', // Latvian
  'lt', // Lithuanian
  'mt', // Maltese
  'pl', // Polish
  'pt', // Portuguese
  'ro', // Romanian
  'sk', // Slovak
  'sl', // Slovenian
  'es', // Spanish
  'sv', // Swedish
  'ru', // Russian
  'uk', // Ukrainian
};

ModelFile _file(String base, String name, int size, String sha) => ModelFile(
  filename: name,
  sizeBytes: size,
  sha256: sha,
  sources: [
    '$base/$name',
    // Public mirror, same LFS SHA-256 and size (verified 2026-11-17).
    // Separate repository; still shares Hugging Face's infrastructure.
    if (base == _whisperBase)
      'https://huggingface.co/osllmai-community/whisper.cpp/resolve/9b8823134f2bff51e5b60e7b5a16a140be0cdb9c/$name',
  ],
);

/// The catalog shipped with this build.
final ModelCatalog bundledModelCatalog = ModelCatalog(
  schemaVersion: kModelCatalogSchemaVersion,
  models: [
    CatalogModel(
      id: CatalogIds.whisperSmall,
      kind: ModelKind.stt,
      runtime: ModelRuntime.whisperCpp,
      label: 'small',
      minAppVersion: _minAppVersion,
      languages: whisperLanguages.keys.toList(),
      speed: ModelLevel.high,
      accuracy: ModelLevel.low,
      requirements: const ModelRequirements(ramMb: 1024, vramMb: 900),
      license: 'MIT',
      files: [
        _file(
          _whisperBase,
          'ggml-small-q5_1.bin',
          190085487,
          'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb',
        ),
      ],
    ),
    CatalogModel(
      id: CatalogIds.whisperMedium,
      kind: ModelKind.stt,
      runtime: ModelRuntime.whisperCpp,
      label: 'medium',
      minAppVersion: _minAppVersion,
      languages: whisperLanguages.keys.toList(),
      speed: ModelLevel.medium,
      accuracy: ModelLevel.medium,
      requirements: const ModelRequirements(ramMb: 2048, vramMb: 1500),
      license: 'MIT',
      files: [
        _file(
          _whisperBase,
          'ggml-medium-q5_0.bin',
          539212467,
          '19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f',
        ),
      ],
    ),
    CatalogModel(
      id: CatalogIds.whisperLargeV3Turbo,
      kind: ModelKind.stt,
      runtime: ModelRuntime.whisperCpp,
      label: 'large-v3-turbo',
      minAppVersion: _minAppVersion,
      languages: whisperLanguages.keys.toList(),
      speed: ModelLevel.medium,
      accuracy: ModelLevel.high,
      requirements: const ModelRequirements(ramMb: 3072, vramMb: 2600),
      license: 'MIT',
      files: [
        _file(
          _whisperBase,
          'ggml-large-v3-turbo-q5_0.bin',
          574041195,
          '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2',
        ),
      ],
    ),
    CatalogModel(
      id: CatalogIds.parakeet,
      kind: ModelKind.stt,
      runtime: ModelRuntime.sherpaOnnx,
      label: 'parakeet-tdt-0.6b-v3 (int8)',
      minAppVersion: _minAppVersion,
      languages: parakeetSupportedLanguages.toList(),
      speed: ModelLevel.high,
      accuracy: ModelLevel.high,
      requirements: const ModelRequirements(ramMb: 1536),
      license: 'CC-BY-4.0',
      files: [
        _file(
          _parakeetOnnxBase,
          'encoder.int8.onnx',
          652184281,
          'acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247',
        ),
        _file(
          _parakeetOnnxBase,
          'decoder.int8.onnx',
          11845275,
          '179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e',
        ),
        _file(
          _parakeetOnnxBase,
          'joiner.int8.onnx',
          6355277,
          '3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3',
        ),
        _file(
          _parakeetOnnxBase,
          'tokens.txt',
          93939,
          'd58544679ea4bc6ac563d1f545eb7d474bd6cfa467f0a6e2c1dc1c7d37e3c35d',
        ),
      ],
    ),
    CatalogModel(
      id: CatalogIds.parakeetGgufQ8,
      kind: ModelKind.stt,
      runtime: ModelRuntime.parakeetGgml,
      label: 'parakeet-tdt-0.6b-v3 (GGUF q8_0)',
      minAppVersion: _minAppVersion,
      languages: parakeetSupportedLanguages.toList(),
      speed: ModelLevel.high,
      accuracy: ModelLevel.high,
      requirements: const ModelRequirements(ramMb: 1024, vramMb: 860),
      license: 'CC-BY-4.0',
      files: [
        _file(
          _parakeetGgufBase,
          'ggml-parakeet-tdt-0.6b-v3-q8_0.bin',
          668757119,
          '4d64e9e96c2792186d072fde0034df0ad670cf680a2f53069052ead827fd600e',
        ),
      ],
    ),
    CatalogModel(
      id: CatalogIds.parakeetGgufF16,
      kind: ModelKind.stt,
      runtime: ModelRuntime.parakeetGgml,
      label: 'parakeet-tdt-0.6b-v3 (GGUF f16)',
      minAppVersion: _minAppVersion,
      languages: parakeetSupportedLanguages.toList(),
      speed: ModelLevel.medium,
      accuracy: ModelLevel.high,
      requirements: const ModelRequirements(ramMb: 1536, vramMb: 1400),
      license: 'CC-BY-4.0',
      files: [
        _file(
          _parakeetGgufBase,
          'ggml-parakeet-tdt-0.6b-v3-f16.bin',
          1255897319,
          '833bffc9513b2cae867ee9e51633cfd11e4d51aaa5597c8ac02159385a2b426f',
        ),
      ],
    ),
    CatalogModel(
      id: CatalogIds.gemma4E2b,
      kind: ModelKind.llm,
      runtime: ModelRuntime.llamaCpp,
      label: 'Gemma 4 E2B',
      minAppVersion: _minAppVersion,
      languages: const [kAnyLanguage],
      speed: ModelLevel.medium,
      accuracy: ModelLevel.medium,
      requirements: const ModelRequirements(ramMb: 4096),
      contextLength: kSmartModeContextLength,
      license: 'Apache-2.0',
      files: [
        _file(
          _gemmaBase,
          'gemma-4-E2B-it-Q4_K_M.gguf',
          3106738272,
          '740185b21d22ceb83a11c3aa62ad5842ef32c70f6096d756bbee85a1e4ec34b8',
        ),
      ],
    ),
  ],
);
