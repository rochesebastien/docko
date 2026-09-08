import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum WallpaperServiceError: LocalizedError {
    case fileNotFound(String)
    case notAnImage(String)
    case copyFailed(Error)
    case applyFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Image de fond d'écran introuvable : \(path)"
        case .notAnImage(let path):
            return "Ce fichier n'est pas une image utilisable comme fond d'écran : \(path)"
        case .copyFailed(let error):
            return "Impossible de copier l'image dans le dossier de Docko (\(error.localizedDescription))."
        case .applyFailed(let screen, let error):
            return "Impossible de changer le fond d'écran de « \(screen) » (\(error.localizedDescription))."
        }
    }
}

/// Fond d'écran associé à un profil : copie de l'image dans le dossier de Docko,
/// application à tous les écrans via `NSWorkspace`, lecture du fond actuel.
///
/// Limite macOS : `setDesktopImageURL` n'agit que sur le Space affiché de chaque écran.
/// Les fonds dynamiques du système (aériens, couleurs) ne sont pas des fichiers image et
/// ne peuvent donc ni être capturés ni être appliqués.
enum WallpaperService {
    /// Types d'image acceptés par le sélecteur. `.image` couvre aussi les HEIC dynamiques clair/sombre.
    static let allowedContentTypes: [UTType] = [.image]

    /// Dossiers dont les images sont référencées telles quelles plutôt que copiées :
    /// ils sont stables et souvent volumineux (HEIC dynamiques de plusieurs dizaines de Mo).
    private static let systemPictureDirectories = [
        "/System/Library/Desktop Pictures",
        "/Library/Desktop Pictures",
    ]

    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Docko", isDirectory: true)
            .appendingPathComponent("Wallpapers", isDirectory: true)
    }

    /// L'image de fond de l'écran principal, si c'est un fichier image lisible. nil sinon.
    static func currentImagePath() -> String? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              url.isFileURL,
              isImageFile(url)
        else { return nil }
        return url.path
    }

    /// Rend l'image utilisable par un profil : copie dans le dossier de Docko (sauf pour
    /// les images système), et renvoie le chemin à mémoriser.
    static func store(_ source: URL) throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else {
            throw WallpaperServiceError.fileNotFound(source.path)
        }
        guard isImageFile(source) else {
            throw WallpaperServiceError.notAnImage(source.path)
        }
        if isManaged(source.path) || isSystemPicture(source.path) {
            return source.path
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = source.pathExtension.isEmpty ? "img" : source.pathExtension
            let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try fm.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            throw WallpaperServiceError.copyFailed(error)
        }
    }

    /// Supprime une copie faite par `store`. Sans effet sur les fichiers hors du dossier de Docko.
    static func discard(_ path: String) {
        guard isManaged(path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Applique l'image à tous les écrans (Space courant de chacun).
    static func apply(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw WallpaperServiceError.fileNotFound(path)
        }
        for screen in NSScreen.screens {
            var options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            // Une image choisie par l'utilisateur doit remplir l'écran, pas rester à sa taille native.
            options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
            } catch {
                throw WallpaperServiceError.applyFailed(screen.localizedName, error)
            }
        }
    }

    static func isManaged(_ path: String) -> Bool {
        path.hasPrefix(directory.path + "/")
    }

    private static func isSystemPicture(_ path: String) -> Bool {
        systemPictureDirectories.contains { path.hasPrefix($0 + "/") }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Vignette réduite, décodée sans charger l'image entière en mémoire.
    static func thumbnail(path: String, maxPixelSize: Int = 320) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
