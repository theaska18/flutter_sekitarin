class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, [this.fields]);

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? fields;

  @override
  String toString() => message;
}
