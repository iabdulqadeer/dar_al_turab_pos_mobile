import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/remote/customer_api.dart';
import '../../../data/models/customer_form.dart';
import '../../auth/providers/auth_providers.dart';

final customerApiProvider = Provider<CustomerApi>((ref) {
  return CustomerApi(ref.watch(apiClientProvider));
});

/// Reference data for the Add Customer screen. Auto-disposed so it is fetched
/// fresh each time the screen opens (groups/areas can change in the back
/// office) rather than cached for the session.
final customerCreateFormProvider = FutureProvider.autoDispose<CustomerCreateForm>(
  (ref) => ref.watch(customerApiProvider).createForm(),
);