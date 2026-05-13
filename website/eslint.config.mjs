// ESLint flat config for the WhisPaste marketing website (Astro/TypeScript).
// Catches the same JS/TS issues that CodeQL security-and-quality flags.
import tsParser from "@typescript-eslint/parser";
import tsPlugin from "@typescript-eslint/eslint-plugin";
import securityPlugin from "eslint-plugin-security";
import globals from "globals";

export default [
  {
    ignores: [
      "dist/**",
      "node_modules/**",
      ".astro/**",
      "*.min.js",
    ],
  },
  // TypeScript / JavaScript sources (Astro files need astro-eslint-parser — excluded)
  {
    files: ["src/**/*.{js,mjs,ts,mts}"],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
      },
      globals: {
        ...globals.browser,
        ...globals.es2021,
      },
    },
    plugins: {
      "@typescript-eslint": tsPlugin,
      security: securityPlugin,
    },
    rules: {
      // CodeQL: js/unused-local-variable
      "no-unused-vars": "off",
      "@typescript-eslint/no-unused-vars": ["error", {
        vars: "all",
        args: "after-used",
        ignoreRestSiblings: true,
        varsIgnorePattern: "^_",
        argsIgnorePattern: "^_",
      }],

      // CodeQL: js/missing-variable-declaration
      "no-undef": "error",

      // CodeQL: js/xss-through-dom (detect-object-injection is too noisy — false positives)
      "no-eval": "error",
      "no-implied-eval": "error",

      // CodeQL: js/unreachable-statement
      "no-unreachable": "error",

      // CodeQL: js/stack-trace-exposure
      "no-console": ["warn", { allow: ["warn", "error"] }],

      // General quality
      "no-var": "error",
      "prefer-const": "error",
    },
  },
];
