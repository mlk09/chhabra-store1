import '../data/models/order.dart';

/// Status buttons the shop sees for an order (same rules as set_order_status in SQL).
List<OrderStatus> nextStatuses(Order o) => switch (o.status) {
  OrderStatus.newOrder => [OrderStatus.accepted, OrderStatus.cancelled],
  OrderStatus.accepted => [OrderStatus.packed, OrderStatus.cancelled],
  OrderStatus.packed => [
    o.fulfilment == Fulfilment.delivery ? OrderStatus.outForDelivery : OrderStatus.readyForPickup,
    OrderStatus.cancelled,
  ],
  OrderStatus.outForDelivery || OrderStatus.readyForPickup => [OrderStatus.delivered, OrderStatus.cancelled],
  OrderStatus.delivered || OrderStatus.cancelled => const [],
};
