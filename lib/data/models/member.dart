/// What the logged-in person may do in this shop.
enum ShopRole { customer, staff, owner }

class Perm {
  const Perm._();
  static const billing = 'billing';
  static const orders = 'orders';
  static const products = 'products';
  static const prices = 'prices';
  static const offers = 'offers';
  static const khata = 'khata';
  static const reports = 'reports';
  static const settings = 'settings';
  static const staff = 'staff';
}

class Membership {
  const Membership(this.role, [this.permissions = const {}]);

  static const customer = Membership(ShopRole.customer);
  static const owner = Membership(ShopRole.owner);

  final ShopRole role;
  final Set<String> permissions;

  bool get isShopkeeper => role != ShopRole.customer;
  bool can(String perm) => role == ShopRole.owner || permissions.contains(perm);
}

class AppUser {
  const AppUser({required this.id, this.email, this.name, this.phone});
  final String id;
  final String? email;
  final String? name;
  final String? phone;
}
