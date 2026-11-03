class PrimeLocation {
  const PrimeLocation(this.id, this.name);
  final String id, name;
  factory PrimeLocation.fromJson(Map<String, dynamic> json) =>
      PrimeLocation(json['id'].toString(), json['name'] as String);
}
