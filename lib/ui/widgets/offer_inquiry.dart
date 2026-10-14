import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../models/offer.dart';
import 'common.dart';

Future<void> inquireAboutOffer(
  BuildContext context,
  TattooOffer offer, {
  bool instagram = false,
}) async {
  final message =
      'مرحبا، أريد أستفسر عن عرض ${offer.name}\n'
      'سعر العرض: ${offer.formattedPrice} (بدون التوصيل)\n'
      '${offer.products.map((p) => '${p.displayName} (${p.code})').join('\n')}';
  try {
    final opened = await launchUrl(
      instagram
          ? Uri.parse(AppConfig.instagramUrl)
          : Uri.parse(AppConfig.whatsappUrl)
                .replace(queryParameters: {'text': message}),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!opened) throw StateError('Could not open chat');
    if (instagram && context.mounted) {
      showNotice(context, 'اذكر عرض «${offer.name}» في محادثة إنستغرام.');
    }
  } catch (_) {
    if (context.mounted) {
      showNotice(
        context,
        instagram
            ? 'تواصل ويانا على Instagram: @${AppConfig.instagramUsername} واذكر عرض «${offer.name}».'
            : 'تواصل ويانا على WhatsApp: 07778700244 واذكر اسم العرض.',
      );
    }
  }
}
