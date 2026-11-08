#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "tree_sitter/api.h"

const TSLanguage *tree_sitter_bash(void);
const TSLanguage *tree_sitter_zsh(void);

static void json_string(const char *s) {
  putchar('"');
  for (const unsigned char *p = (const unsigned char *)s; *p; ++p) {
    switch (*p) {
      case '"': fputs("\\\"", stdout); break;
      case '\\': fputs("\\\\", stdout); break;
      case '\n': fputs("\\n", stdout); break;
      case '\r': fputs("\\r", stdout); break;
      case '\t': fputs("\\t", stdout); break;
      default:
        if (*p < 0x20) printf("\\u%04x", *p);
        else putchar(*p);
    }
  }
  putchar('"');
}

static bool within_bounds(TSNode node, unsigned depth, uint32_t *count) {
  if (depth > 128 || ++*count > 100000) return false;
  uint32_t children = ts_node_child_count(node);
  for (uint32_t i = 0; i < children; ++i) {
    if (!within_bounds(ts_node_child(node, i), depth + 1, count)) return false;
  }
  return true;
}

static void emit_node(TSNode node, const char *field) {
  fputs("{\"type\":", stdout); json_string(ts_node_type(node));
  printf(",\"start_byte\":%" PRIu32 ",\"end_byte\":%" PRIu32,
         ts_node_start_byte(node), ts_node_end_byte(node));
  fputs(",\"field\":", stdout);
  if (field) json_string(field); else fputs("null", stdout);
  printf(",\"named\":%s,\"error\":%s,\"has_error\":%s,\"missing\":%s,\"children\":[",
         ts_node_is_named(node) ? "true" : "false",
         ts_node_is_error(node) ? "true" : "false",
         ts_node_has_error(node) ? "true" : "false",
         ts_node_is_missing(node) ? "true" : "false");
  uint32_t count = ts_node_child_count(node);
  for (uint32_t i = 0; i < count; ++i) {
    if (i) putchar(',');
    emit_node(ts_node_child(node, i), ts_node_field_name_for_child(node, i));
  }
  fputs("]}", stdout);
}

int main(int argc, char **argv) {
  if (argc != 2 || (strcmp(argv[1], "bash") != 0 && strcmp(argv[1], "zsh") != 0)) {
    fputs("usage: tsparse bash|zsh < command\n", stderr);
    return 2;
  }
  const TSLanguage *language = strcmp(argv[1], "bash") == 0 ? tree_sitter_bash() : tree_sitter_zsh();
  TSParser *parser = ts_parser_new();
  if (!parser || !ts_parser_set_language(parser, language)) {
    fputs("incompatible grammar ABI\n", stderr);
    ts_parser_delete(parser);
    return 4;
  }
  const size_t limit = 1024 * 1024;
  char *input = malloc(limit + 1);
  if (!input) { ts_parser_delete(parser); return 4; }
  size_t size = 0;
  while (size < limit + 1) {
    size_t got = fread(input + size, 1, limit + 1 - size, stdin);
    size += got;
    if (got == 0) break;
  }
  if (ferror(stdin) || size > limit || memchr(input, '\0', size)) {
    fputs("input read error, too large, or NUL byte\n", stderr);
    free(input); ts_parser_delete(parser); return 4;
  }
  TSTree *tree = ts_parser_parse_string(parser, NULL, input, (uint32_t)size);
  if (!tree) { free(input); ts_parser_delete(parser); return 4; }
  uint32_t node_count = 0;
  TSNode root = ts_tree_root_node(tree);
  if (!within_bounds(root, 0, &node_count)) {
    fputs("parse tree depth or node limit exceeded\n", stderr);
    ts_tree_delete(tree); ts_parser_delete(parser); free(input);
    return 4;
  }
  emit_node(root, NULL);
  putchar('\n');
  int output_error = fflush(stdout) == EOF || ferror(stdout);
  ts_tree_delete(tree); ts_parser_delete(parser); free(input);
  return output_error ? 4 : 0;
}
