using Windows.Data.Pdf;
using Windows.Storage;
using Windows.Storage.Streams;

if (args.Length < 2)
{
    Console.WriteLine("usage: PdfCheck <pdf> <output.png>");
    return 2;
}

var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(args[0]));
var document = await PdfDocument.LoadFromFileAsync(file);
Console.WriteLine($"PAGES={document.PageCount}");

using var page = document.GetPage(0);
using var stream = new InMemoryRandomAccessStream();
await page.RenderToStreamAsync(stream);
stream.Seek(0);

var buffer = new byte[checked((int)stream.Size)];
using (var reader = new DataReader(stream.GetInputStreamAt(0)))
{
    await reader.LoadAsync((uint)stream.Size);
    reader.ReadBytes(buffer);
}

await File.WriteAllBytesAsync(Path.GetFullPath(args[1]), buffer);
Console.WriteLine($"RENDERED={buffer.Length}");
return 0;
