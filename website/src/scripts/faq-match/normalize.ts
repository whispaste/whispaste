/**
 * Text normalisation and feature extraction for the FAQ matcher (#351).
 *
 * A question and every FAQ document go through the same pipeline, so the
 * matcher compares like with like:
 *   - Unicode NFKD, lower case, combining marks dropped (ä → a, é → e),
 *     ß → ss, ё → е: spelling without umlauts or accents still matches.
 *   - Words (`w:`), their first five letters (`p:`, a cheap stand-in for
 *     stemming: "kostet"/"kosten", "download"/"downloads") and boundary-marked
 *     character 3-grams (`g:`, tolerance for typos).
 *   - Chinese has no spaces: a run of CJK characters yields overlapping
 *     bigrams as words and single characters as grams.
 *   - Negations become a `neg` feature instead of being dropped as stop words,
 *     and error codes (0x80070005, 404) count double.
 *
 * Pure functions, no dictionaries: the browser bundle can import this file.
 */

export type Feature = string;

/** Weighted bag of features: feature → summed weight. */
export type FeatureBag = Map<Feature, number>;

/** Relative weight of each feature family in the score. */
export const FEATURE_WEIGHT = { w: 1, p: 0.6, g: 0.25, neg: 0.5 } as const;

const CJK = /[㐀-鿿豈-﫿]/u;

/** Words that carry no topic in any of the site languages. */
const STOP_WORDS = new Set(
  [
    // en
    'a an and any are as at be by can could do does for from get has have how i if in is it its me my of on or so that the there this to use using what when where which who why will with would you your',
    // de
    'am an auch auf aus bei bin bitte das dass dem den der des die du ein eine einem einen einer es fur gibt habe hat ich im in ist ja kann man mein meine meinen mir mit muss oder sie sich sind und uber von was welche welchen welcher welches wenn wie wird wo zu',
    // generic verbs ("does not work" says nothing about the topic)
    'work works working funktioniert funktionieren klappt funciona funcionar funcionan funziona funzionare работает работать marche fonctionne',
    'change changes ander andern andert verandert verandern cambia cambiar cambio muda mudar mudo cambiare cambio changer change меняет менять изменить',
    // es
    'a como con cual cuando de del el en es la las lo los mi para por que se un una y',
    // pt
    'a as com como de do da e em eu meu minha o os para por qual quando que se um uma',
    // it
    'a che come con cosa da di e il in io la le lo mi mio per quale quando se si un una',
    // ru
    'а в и как какие какой ли мне мой на о по с что это я',
    // fr
    'a au avec ce comment de des du en est et il je la le les ma mon on ou pour quand que quel quelle qui un une',
  ]
    .join(' ')
    .split(' '),
);

/** Negation words; they stay meaningful ("does not start", "geht nicht"). */
const NEGATIONS = new Set(
  'not no never cannot cant dont doesnt isnt wont nicht kein keine keinen nie nao non pas jamais ne нет не никак'.split(' '),
);

const ERROR_CODE = /^(?:0x[0-9a-f]{4,}|\d{3,})$/u;

/** NFKD, lower case, marks stripped, a few letter folds. */
export function fold(text: string): string {
  return text
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLowerCase()
    .replace(/ß/gu, 'ss')
    .replace(/ё/gu, 'е')
    .replace(/[’`´]/gu, "'")
    .replace(/'/gu, '');
}

function add(bag: FeatureBag, feature: Feature, weight: number): void {
  bag.set(feature, (bag.get(feature) ?? 0) + weight);
}

function addWord(bag: FeatureBag, word: string, weight: number): void {
  const w = ERROR_CODE.test(word) ? weight * 2 : weight;
  add(bag, `w:${word}`, w);
  if (word.length > 5) add(bag, `p:${word.slice(0, 5)}`, w);
  const marked = `#${word}#`;
  for (let i = 0; i + 3 <= marked.length; i++) add(bag, `g:${marked.slice(i, i + 3)}`, w);
}

function addCjkRun(bag: FeatureBag, run: string, weight: number): void {
  const chars = Array.from(run);
  for (const ch of chars) add(bag, `g:${ch}`, weight);
  if (chars.length === 1) add(bag, `w:${chars[0]}`, weight);
  for (let i = 0; i + 2 <= chars.length; i++) add(bag, `w:${chars[i]}${chars[i + 1]}`, weight);
  if (/[不没無无别]/u.test(run)) add(bag, 'neg', weight);
}

/**
 * Adds the features of [text] to [bag] with [weight] (field weight: question
 * text counts more than the answer body).
 */
export function addFeatures(bag: FeatureBag, text: string, weight = 1): FeatureBag {
  const folded = fold(text);
  for (const token of folded.match(/[\p{L}\p{N}]+/gu) ?? []) {
    if (CJK.test(token)) {
      // Split mixed tokens ("windows为什么") into CJK runs and the rest.
      for (const part of token.match(/[㐀-鿿豈-﫿]+|[^㐀-鿿豈-﫿]+/gu) ?? []) {
        if (CJK.test(part)) addCjkRun(bag, part, weight);
        else if (!STOP_WORDS.has(part)) addWord(bag, part, weight);
      }
      continue;
    }
    if (NEGATIONS.has(token)) {
      add(bag, 'neg', weight);
      continue;
    }
    if (token.length < 2 || STOP_WORDS.has(token)) continue;
    addWord(bag, token, weight);
  }
  return bag;
}

/** Features of a single text. */
export function features(text: string): FeatureBag {
  return addFeatures(new Map(), text);
}

/** Weight of a feature family, from its prefix. */
export function familyWeight(feature: Feature): number {
  if (feature === 'neg') return FEATURE_WEIGHT.neg;
  const family = feature.slice(0, 1) as 'w' | 'p' | 'g';
  return FEATURE_WEIGHT[family];
}
