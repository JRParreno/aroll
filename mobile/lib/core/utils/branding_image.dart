import 'dart:io' show Platform;

import 'package:aroll_mobile/core/utils/data_uri_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Origin of the API server (scheme + host + port), derived from [API_BASE_URL].
String? apiServerOrigin() {
  final base = dotenv.env['API_BASE_URL'] ?? _defaultApiBaseUrl();
  final uri = Uri.tryParse(base);
  if (uri == null || uri.host.isEmpty) return null;
  final portPart = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$portPart';
}

/// Resolves a remote business logo URL for [NetworkImage] / [Image.network].
///
/// Handles absolute http(s) URLs, root-relative paths (`/uploads/...`), and
/// rewrites localhost/127.0.0.1 to match [API_BASE_URL] on physical devices.
/// Returns null for data URIs (use [brandingImageProvider] instead).
String? resolveRemoteBrandingImageUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('data:')) return null;

  final Uri? parsed;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    parsed = Uri.tryParse(trimmed);
  } else {
    final origin = apiServerOrigin();
    if (origin == null) return null;
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    parsed = Uri.tryParse('$origin$path');
  }
  if (parsed == null) return null;

  return _rewriteLocalhostForDevice(parsed).toString();
}

Uri _rewriteLocalhostForDevice(Uri imageUri) {
  final origin = apiServerOrigin();
  if (origin == null) return imageUri;

  final apiUri = Uri.parse(origin);
  const deviceUnreachableHosts = {'localhost', '127.0.0.1'};
  if (!deviceUnreachableHosts.contains(imageUri.host)) {
    return imageUri;
  }
  if (deviceUnreachableHosts.contains(apiUri.host)) {
    return imageUri;
  }

  return imageUri.replace(
    scheme: apiUri.scheme,
    host: apiUri.host,
    port: apiUri.hasPort ? apiUri.port : imageUri.port,
  );
}

/// Data URI → [MemoryImage]; remote URL → [NetworkImage].
ImageProvider? brandingImageProvider(String? url) {
  if (url == null || url.trim().isEmpty) return null;

  final bytes = dataUriBytes(url);
  if (bytes != null) return MemoryImage(bytes);

  final remote = resolveRemoteBrandingImageUrl(url);
  if (remote != null) return NetworkImage(remote);

  return null;
}

String _defaultApiBaseUrl() {
  if (Platform.isAndroid) {
    return 'http://10.0.2.2:8000/api/v1';
  }
  return 'http://127.0.0.1:8000/api/v1';
}
