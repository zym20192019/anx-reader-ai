import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/book.dart';

class BookDao extends BaseDao {
  BookDao();

  static const String table = 'tb_books';

  Future<int> save(Book book) async {
    if (book.id != -1) {
      await updateBook(book);
      return book.id;
    }
    return insert(table, book.toMap());
  }

  Future<int> insertBook(Book book) => save(book);

  Future<void> updateBook(Book book) async {
    book.updateTime = DateTime.now();
    await update(
      table,
      book.toMap(),
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  Future<List<Book>> selectBooks({bool includeDeleted = true}) {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectNotDeleteBooks() {
    return selectBooks(includeDeleted: false);
  }

  Future<Book> selectBookById(int id) async {
    final book = await querySingle(
      table,
      mapper: Book.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (book == null) {
      throw StateError('Book with id $id not found');
    }
    return book;
  }

  Future<List<String>> getCurrentBooks() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.filePath).toList(growable: false);
  }

  Future<List<String>> getCurrentCover() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.coverPath).toList(growable: false);
  }

  Future<List<Book>> selectAllBooks() {
    return selectBooks();
  }

  @Deprecated('Use getBookByFileMd5 or getBookBySourceMd5 instead')
  Future<Book?> getBookByMd5(String md5) {
    return getBookByFileMd5(md5);
  }

  Future<Book?> getBookByFileMd5(String fileMd5) {
    return querySingle(
      table,
      mapper: Book.fromDb,
      where: 'file_md5 = ?',
      whereArgs: [fileMd5],
    );
  }

  Future<Book?> getBookBySourceMd5(String sourceMd5) {
    return querySingle(
      table,
      mapper: Book.fromDb,
      where: 'source_md5 = ?',
      whereArgs: [sourceMd5],
    );
  }

  Future<Book?> getLegacyBookByFileMd5(String fileMd5) {
    return querySingle(
      table,
      mapper: Book.fromDb,
      where: "(source_md5 IS NULL OR source_md5 = '') AND file_md5 = ?",
      whereArgs: [fileMd5],
    );
  }

  Future<List<Book>> searchBooks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    return queryList(
      table,
      mapper: Book.fromDb,
      where: 'is_deleted = 0 AND (title LIKE ? OR author LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectBooksByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    return rawQueryList(
      'SELECT * FROM $table WHERE is_deleted = 0 AND id IN ($placeholders)',
      arguments: ids,
      mapper: Book.fromDb,
    );
  }

  Future<void> updateBookMd5(int bookId, String md5) {
    return update(
      table,
      {
        'file_md5': md5,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<void> updateBookFileMd5(int bookId, String fileMd5) =>
      updateBookMd5(bookId, fileMd5);

  Future<void> updateBookSourceMd5(int bookId, String sourceMd5) {
    return update(
      table,
      {
        'source_md5': sourceMd5,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<Book>> getBooksWithoutMd5() {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: "is_deleted = 0 AND (file_md5 IS NULL OR file_md5 = '')",
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> getBooksWithoutFileMd5() => getBooksWithoutMd5();

  Future<List<Book>> getBooksWithoutSourceMd5() {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: "is_deleted = 0 AND (source_md5 IS NULL OR source_md5 = '')",
      orderBy: 'update_time DESC',
    );
  }
}

final bookDao = BookDao();
