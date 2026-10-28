class Category {
  const Category({
    required this.id,
    required this.name,
    this.nameHi,
    this.icon,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? nameHi;
  final String? icon;
  final int sortOrder;
  final bool isActive;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
    id: j['id'] as String,
    name: j['name'] as String,
    nameHi: j['name_hi'] as String?,
    icon: j['icon'] as String?,
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    isActive: j['is_active'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'name_hi': nameHi,
    'icon': icon,
    'sort_order': sortOrder,
    'is_active': isActive,
  };

  Category copyWith({String? name, String? nameHi, String? icon, int? sortOrder, bool? isActive}) => Category(
    id: id,
    name: name ?? this.name,
    nameHi: nameHi ?? this.nameHi,
    icon: icon ?? this.icon,
    sortOrder: sortOrder ?? this.sortOrder,
    isActive: isActive ?? this.isActive,
  );
}
