using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace WnacgDownloader.Core;

/// <summary>
/// Minimal PDF 1.4 writer: every page is one full-bleed JPEG image embedded
/// with DCTDecode, so no extra PDF library is required and JPEG bytes are
/// never re-encoded.
/// </summary>
public static class PdfBuilder
{
    // Every page has the same width (A4 width in points), like the iOS app.
    // Mixed portrait/landscape pages then line up in PDF viewers instead of
    // landscape pages appearing wider than portrait ones.
    public const double PageWidth = 595.0;

    private static readonly HashSet<string> ImageExtensions =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp",
        };

    public static (int Pages, int Skipped) BuildFromDirectory(
        string directory,
        string outputPath,
        IProgress<DownloadProgress>? progress = null,
        CancellationToken ct = default
    )
    {
        var files = Directory
            .GetFiles(directory)
            .Where(f => ImageExtensions.Contains(Path.GetExtension(f)))
            .OrderBy(f => f, StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (files.Count == 0)
        {
            throw new WnacgException("目录里没有图片，无法生成 PDF。");
        }

        var partPath = outputPath + ".part";
        try
        {
            if (File.Exists(partPath))
            {
                File.Delete(partPath);
            }

            var pages = 0;
            var skipped = 0;
            var total = files.Count;

            using (var stream = new FileStream(
                partPath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                1 << 20
            ))
            {
                var writer = new PdfWriter(stream);
                foreach (var file in files)
                {
                    ct.ThrowIfCancellationRequested();
                    var data = File.ReadAllBytes(file);
                    if (!TryGetJpegSize(data, out var width, out var height, out var components) ||
                        (components != 1 && components != 3))
                    {
                        // Only JPEG can be embedded verbatim. The site's
                        // reader pages are JPEG; non-JPEG pages are skipped
                        // rather than silently swapped for a broken page.
                        skipped++;
                    }
                    else
                    {
                        writer.AddPage(
                            width,
                            height,
                            components == 1 ? "/DeviceGray" : "/DeviceRGB",
                            data
                        );
                        pages++;
                    }

                    var done = pages + skipped;
                    if (done % 5 == 0 || done == total)
                    {
                        progress?.Report(
                            new DownloadProgress(
                                done,
                                total,
                                0,
                                "正在生成 PDF"
                            )
                        );
                    }
                }

                if (pages == 0)
                {
                    throw new WnacgException(
                        "所有图片都不是可嵌入的 JPEG，PDF 未生成。"
                    );
                }

                writer.Finish();
                stream.Flush();
            }

            File.Move(partPath, outputPath, overwrite: true);
            return (pages, skipped);
        }
        catch
        {
            try
            {
                if (File.Exists(partPath))
                {
                    File.Delete(partPath);
                }
            }
            catch
            {
                // Keep the original exception.
            }

            throw;
        }
    }

    /// <summary>Reads (width, height, components) from a JPEG SOF marker.</summary>
    public static bool TryGetJpegSize(
        byte[] data,
        out int width,
        out int height,
        out int components
    )
    {
        width = 0;
        height = 0;
        components = 0;
        if (data.Length < 4 || data[0] != 0xFF || data[1] != 0xD8)
        {
            return false;
        }

        var offset = 2;
        while (offset + 4 <= data.Length)
        {
            if (data[offset] != 0xFF)
            {
                offset++;
                continue;
            }

            var marker = data[offset + 1];
            if (marker == 0xFF)
            {
                offset++;
                continue;
            }

            if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7))
            {
                offset += 2;
                continue;
            }

            if (marker == 0xD9 || marker == 0xDA)
            {
                break;
            }

            var segmentLength = (data[offset + 2] << 8) | data[offset + 3];
            if (segmentLength < 2)
            {
                break;
            }

            if (marker is 0xC0 or 0xC1 or 0xC2 or 0xC3 or 0xC5 or 0xC6 or 0xC7
                or 0xC9 or 0xCA or 0xCB or 0xCD or 0xCE or 0xCF)
            {
                if (offset + 10 > data.Length)
                {
                    break;
                }

                var precision = data[offset + 4];
                height = (data[offset + 5] << 8) | data[offset + 6];
                width = (data[offset + 7] << 8) | data[offset + 8];
                components = data[offset + 9];
                if (width > 0 && height > 0)
                {
                    return precision == 8;
                }

                return false;
            }

            offset += 2 + segmentLength;
        }

        return false;
    }

    private sealed class PdfWriter
    {
        private readonly Stream _stream;
        private readonly Dictionary<int, long> _offsets = new();
        private readonly List<int> _pageObjects = new();
        private int _nextObject = 3; // 1 = Catalog, 2 = Pages

        public PdfWriter(Stream stream)
        {
            _stream = stream;
            WriteAscii("%PDF-1.4\n%\u00e2\u00e3\u00cf\u00d3\n");
        }

        public void AddPage(
            int width,
            int height,
            string colorSpace,
            byte[] jpeg
        )
        {
            var pageObject = _nextObject;
            var imageObject = pageObject + 1;
            var contentObject = pageObject + 2;
            _nextObject += 3;
            _pageObjects.Add(pageObject);

            var widthPt = PageWidth;
            var heightPt = Math.Max(1.0, height * (PageWidth / Math.Max(1, width)));
            var cp = CultureInfo.InvariantCulture;

            var imageBody =
                $"<< /Type /XObject /Subtype /Image /Width {width} " +
                $"/Height {height} /ColorSpace {colorSpace} " +
                $"/BitsPerComponent 8 /Filter /DCTDecode /Length {jpeg.Length} >>";
            WriteObject(imageObject, Encoding.ASCII.GetBytes(imageBody), jpeg);

            var content =
                $"q\n{widthPt.ToString("0.###", cp)} 0 0 " +
                $"{heightPt.ToString("0.###", cp)} 0 0 cm\n/Im0 Do\nQ\n";
            var contentBytes = Encoding.ASCII.GetBytes(content);
            WriteObject(
                contentObject,
                Encoding.ASCII.GetBytes($"<< /Length {contentBytes.Length} >>"),
                contentBytes
            );

            var pageBody =
                $"<< /Type /Page /Parent 2 0 R " +
                $"/MediaBox [0 0 {widthPt.ToString("0.###", cp)} " +
                $"{heightPt.ToString("0.###", cp)}] " +
                $"/Resources << /XObject << /Im0 {imageObject} 0 R >> >> " +
                $"/Contents {contentObject} 0 R >>";
            WriteObject(pageObject, Encoding.ASCII.GetBytes(pageBody));
        }

        public void Finish()
        {
            var kids = string.Join(
                " ",
                _pageObjects.Select(number => $"{number} 0 R")
            );
            WriteObject(1, Encoding.ASCII.GetBytes("<< /Type /Catalog /Pages 2 0 R >>"));
            WriteObject(
                2,
                Encoding.ASCII.GetBytes(
                    $"<< /Type /Pages /Kids [{kids}] /Count {_pageObjects.Count} >>"
                )
            );

            var xrefOffset = _stream.Position;
            var totalObjects = _nextObject - 1;
            WriteAscii($"xref\n0 {totalObjects + 1}\n");
            WriteAscii("0000000000 65535 f \n");
            for (var number = 1; number <= totalObjects; number++)
            {
                if (!_offsets.TryGetValue(number, out var offset))
                {
                    throw new WnacgException($"PDF 写入异常：对象 {number} 缺失");
                }

                WriteAscii($"{offset:0000000000} 00000 n \n");
            }

            WriteAscii(
                "trailer\n" +
                $"<< /Size {totalObjects + 1} /Root 1 0 R >>\n" +
                $"startxref\n{xrefOffset}\n%%EOF\n"
            );
        }

        private void WriteObject(int number, byte[] body, byte[]? stream = null)
        {
            _offsets[number] = _stream.Position;
            WriteAscii($"{number} 0 obj\n");
            _stream.Write(body);
            if (stream != null)
            {
                WriteAscii("\nstream\n");
                _stream.Write(stream);
                WriteAscii("\nendstream");
            }

            WriteAscii("\nendobj\n");
        }

        private void WriteAscii(string text)
        {
            _stream.Write(Encoding.ASCII.GetBytes(text));
        }
    }

    public static bool LooksLikeValidPdf(string path)
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length < 100)
            {
                return false;
            }

            using var stream = File.OpenRead(path);
            var head = new byte[8];
            var read = stream.Read(head, 0, head.Length);
            stream.Seek(Math.Max(0, stream.Length - 4096), SeekOrigin.Begin);
            var tail = new byte[4096];
            var tailRead = stream.Read(tail, 0, tail.Length);
            var headText = Encoding.ASCII.GetString(head, 0, read);
            var tailText = Encoding.ASCII.GetString(tail, 0, tailRead);
            return headText.StartsWith("%PDF-", StringComparison.Ordinal)
                && tailText.Contains("%%EOF", StringComparison.Ordinal);
        }
        catch
        {
            return false;
        }
    }

    public static int CountPages(string path)
    {
        try
        {
            var text = File.ReadAllText(path, Encoding.Latin1);
            return Regex.Matches(text, "/Type\\s*/Page[^s]").Count;
        }
        catch
        {
            return 0;
        }
    }
}
