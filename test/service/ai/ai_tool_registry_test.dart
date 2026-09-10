import 'package:anx_reader/service/ai/langchain_registry.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:test/test.dart';

void main() {
  test('marks only plan-producing tools as requiring user confirmation', () {
    final confirmationIds = AiToolRegistry.definitions
        .where((definition) => definition.requiresUserConfirmation)
        .map((definition) => definition.id)
        .toList();

    expect(
      confirmationIds,
      unorderedEquals(['bookshelf_organize', 'apply_book_tags']),
    );
    expect(
      AiToolRegistry.byId('workspace_overview')!.requiresUserConfirmation,
      isFalse,
    );
  });

  test('marks confirmation-required tools in the system prompt catalog', () {
    final catalog = formatAiToolCatalog([
      AiToolRegistry.byId('bookshelf_organize')!,
      AiToolRegistry.byId('apply_book_tags')!,
      AiToolRegistry.byId('workspace_overview')!,
    ]);
    final lines = catalog.split('\n');
    final confirmationLines =
        lines.where((line) => line.contains('REQUIRES USER CONFIRMATION'));

    expect(confirmationLines, hasLength(2));
    expect(
      confirmationLines,
      everyElement(contains('review this plan with the user')),
    );
    expect(
      confirmationLines,
      everyElement(contains('explicit approval before applying')),
    );
    expect(
      confirmationLines,
      everyElement(contains('does not apply changes')),
    );
    expect(lines.last, isNot(contains('REQUIRES USER CONFIRMATION')));
  });
}
