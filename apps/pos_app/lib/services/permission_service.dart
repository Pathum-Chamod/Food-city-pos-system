import 'package:shared/shared.dart';

class PosPermission {
  const PosPermission._();

  static const posSell = 'pos.sell';
  static const posHoldCart = 'pos.hold_cart';
  static const posSelectCustomer = 'pos.select_customer';
  static const posCashPayment = 'pos.cash_payment';
  static const posCardPayment = 'pos.card_payment';
  static const posCustomerCreditPaymentMethod =
      'pos.customer_credit_payment_method';
  static const posApplySmallDiscount = 'pos.apply_small_discount';
  static const posLargeDiscount = 'pos.large_discount';
  static const posPriceOverride = 'pos.price_override';
  static const posRefund = 'pos.refund';

  static const inventoryView = 'inventory.view';
  static const inventoryAdjust = 'inventory.adjust';
  static const inventoryPriceUpdate = 'inventory.price_update';

  static const customersView = 'customers.view';
  static const customersManage = 'customers.manage';

  static const customerCreditManage = 'customer_credit.manage';
  static const customerCreditReceivePayment = 'customer_credit.receive_payment';
  static const customerCreditAdjust = 'customer_credit.adjust';
  static const customerCreditVoidPayment = 'customer_credit.void_payment';

  static const pricingManage = 'pricing.manage';

  static const loyaltyRedeem = 'loyalty.redeem';
  static const loyaltyAdjust = 'loyalty.adjust';

  static const reportsView = 'reports.view';
  static const reportsShiftOwn = 'reports.shift_own';

  static const backupCreate = 'backup.create';
  static const backupRestore = 'backup.restore';

  static const usersManage = 'users.manage';
  static const settingsManage = 'settings.manage';
}

class PermissionService {
  PermissionService._();

  static const double cashierMaxDiscountPercent = 5;

  static const Set<String> managerPermissions = {
    PosPermission.posSell,
    PosPermission.posHoldCart,
    PosPermission.posSelectCustomer,
    PosPermission.posCashPayment,
    PosPermission.posCardPayment,
    PosPermission.posCustomerCreditPaymentMethod,
    PosPermission.posApplySmallDiscount,
    PosPermission.posLargeDiscount,
    PosPermission.posPriceOverride,
    PosPermission.posRefund,
    PosPermission.inventoryView,
    PosPermission.inventoryAdjust,
    PosPermission.inventoryPriceUpdate,
    PosPermission.customersView,
    PosPermission.customersManage,
    PosPermission.customerCreditManage,
    PosPermission.customerCreditReceivePayment,
    PosPermission.customerCreditAdjust,
    PosPermission.customerCreditVoidPayment,
    PosPermission.pricingManage,
    PosPermission.loyaltyRedeem,
    PosPermission.loyaltyAdjust,
    PosPermission.reportsView,
    PosPermission.reportsShiftOwn,
    PosPermission.backupCreate,
    PosPermission.backupRestore,
    PosPermission.usersManage,
    PosPermission.settingsManage,
  };

  static const Set<String> cashierPermissions = {
    PosPermission.posSell,
    PosPermission.posHoldCart,
    PosPermission.posSelectCustomer,
    PosPermission.posCashPayment,
    PosPermission.posCardPayment,
    PosPermission.posCustomerCreditPaymentMethod,
    PosPermission.posApplySmallDiscount,
    PosPermission.customersView,
    PosPermission.customersManage,
    PosPermission.inventoryView,
    PosPermission.loyaltyRedeem,
    PosPermission.reportsShiftOwn,
  };

  static String normalizeRole(String? role) => User.normalizeRole(role);

  static bool isManagerRole(String? role) =>
      normalizeRole(role) == User.managerRole;

  static bool isCashierRole(String? role) =>
      normalizeRole(role) == User.cashierRole;

  static bool hasManagementAccess(User? user) {
    if (user == null || !user.isActive) return false;
    return user.isManager || user.hasFullAccess;
  }

  static bool can(User? user, String permission) {
    if (user == null || !user.isActive) return false;
    if (hasManagementAccess(user)) {
      return managerPermissions.contains(permission);
    }
    if (user.isCashier) return cashierPermissions.contains(permission);
    return false;
  }

  static bool roleCan(
    String? role,
    String permission, {
    bool hasFullAccess = false,
  }) {
    if (hasFullAccess) return managerPermissions.contains(permission);
    final normalizedRole = normalizeRole(role);
    if (normalizedRole == User.managerRole) {
      return managerPermissions.contains(permission);
    }
    if (normalizedRole == User.cashierRole) {
      return cashierPermissions.contains(permission);
    }
    return false;
  }

  static bool requiresManagerApproval(User? user, String permission) {
    if (can(user, permission)) return false;
    return managerPermissions.contains(permission);
  }

  static bool isDiscountWithinCashierLimit(double percent) {
    return percent >= 0 && percent <= cashierMaxDiscountPercent;
  }
}
