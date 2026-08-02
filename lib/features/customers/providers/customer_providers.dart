import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/remote/customer_api.dart';
import '../../auth/providers/auth_providers.dart';

final customerApiProvider = Provider<CustomerApi>((ref) {
  return CustomerApi(ref.watch(apiClientProvider));
});