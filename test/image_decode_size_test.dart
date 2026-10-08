import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/widgets/seller_avatar.dart';
import 'package:pokepedia_mobile/shared/widgets/user_avatar.dart';

/// Store logos, avatars and banners are uploaded straight from phone
/// cameras. Decoded at that size, one 4000px photo is tens of megabytes of
/// bitmap for a 32pt circle — enough, on a store whose images were large,
/// for the OS to kill the app as the page opened. Each is decoded at the
/// size it is drawn instead.
void main() {
  Future<ResizeImage> decodedAs(WidgetTester tester, Widget avatar) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: avatar)),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<ResizeImage>(),
      reason: 'decoded whole, at whatever size was uploaded',
    );
    return image.image as ResizeImage;
  }

  testWidgets('a seller avatar is decoded at its drawn size', (tester) async {
    final image = await decodedAs(
      tester,
      const SellerAvatar(
        name: 'Toko',
        imageUrl: 'https://example.com/logo.jpg',
        size: 32,
      ),
    );
    expect(image.width, 96);
  });

  testWidgets('so is a user avatar', (tester) async {
    final image = await decodedAs(
      tester,
      const UserAvatar(
        username: 'panda',
        imageUrl: 'https://example.com/me.jpg',
        size: 48,
      ),
    );
    expect(image.width, 144);
  });
}
