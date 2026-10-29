import 'models.dart';

abstract class IEventRepository {
  Future<AppSnapshot> loadAll();
  Future<int> create(EventItem item);
  Future<void> update(EventItem item);
  Future<void> delete(int id);
  Future<void> overrideOccurrence(EventException exception);
  Future<void> setStatus(EventOccurrence occurrence, String status);
  Future<void> createCategory(String name, String colorHex);
  Future<void> updateCategory(Category category);
  Future<void> deleteCategory(int id);
  Future<void> setSetting(String key, String value);
  Future<String> exportJson();
  Future<void> importJson(String json);
}
