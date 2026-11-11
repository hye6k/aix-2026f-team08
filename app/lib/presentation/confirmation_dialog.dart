import 'package:flutter/material.dart';

/// 한 번의 확인으로 뒤의 화면까지 연속해서 닫히지 않도록 처리한다.
Future<bool> showConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '취소',
}) async {
  var decided = false;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          void finish(bool value) {
            if (decided ||
                !dialogContext.mounted ||
                ModalRoute.of(dialogContext)?.isCurrent != true) {
              return;
            }
            decided = true;
            Navigator.of(dialogContext).pop(value);
          }

          return AlertDialog(
            scrollable: true,
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => finish(false),
                child: Text(cancelLabel),
              ),
              TextButton(
                onPressed: () => finish(true),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ) ??
      false;
}
