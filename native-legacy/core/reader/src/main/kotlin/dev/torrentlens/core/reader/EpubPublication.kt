package dev.torrentlens.core.reader

import java.io.File
import java.io.StringReader
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
import org.xml.sax.InputSource

/**
 * EPUB container navigation: `META-INF/container.xml` → package document (OPF) →
 * manifest + spine.
 *
 * This is the *structure* layer: it yields an ordered spine, resolved hrefs and
 * the resources needed to render a chapter. Presentation (typography, themes,
 * page/scroll modes, RTL) is the UI's job, and swapping in a full rendering
 * engine such as Readium later only affects how a resolved href is displayed —
 * not how the spine is discovered. See docs/adr/0003.
 */
class EpubPublication private constructor(
    private val zip: ZipFile,
    val packagePath: String,
    val title: String?,
    val language: String?,
    /** Reading order, as archive paths resolved against the OPF directory. */
    val spineHrefs: List<String>,
    private val resources: Map<String, String>,
) : AutoCloseable {

    /** MIME type declared in the manifest for an archive path, if any. */
    fun mediaTypeOf(path: String): String? = resources[path]

    val chapterCount: Int get() = spineHrefs.size

    fun exists(path: String): Boolean = zip.getEntry(path) != null

    fun read(path: String): ByteArray? {
        val entry = zip.getEntry(path) ?: return null
        return zip.getInputStream(entry).use { it.readBytes() }
    }

    fun readText(path: String): String? = read(path)?.toString(Charsets.UTF_8)

    /**
     * Every archive path the OPF manifest declares, paired with its media type.
     * Used to prime the isolated viewer's asset loader for relative references.
     */
    fun manifestEntries(): Map<String, String> = resources

    override fun close() = zip.close()

    companion object {

        fun open(file: File): Result<EpubPublication> = runCatching {
            val zip = ZipFile(file)
            try {
                val containerPath = "META-INF/container.xml"
                val container = zip.getEntry(containerPath)?.let { entry ->
                    zip.getInputStream(entry).use { it.readBytes().toString(Charsets.UTF_8) }
                } ?: throw EpubFormatException("Not an EPUB: missing META-INF/container.xml")

                val packagePath = parseContainer(container)
                    ?: throw EpubFormatException("EPUB container does not declare a rootfile")

                val opfXml = zip.getEntry(packagePath)?.let { entry ->
                    zip.getInputStream(entry).use { it.readBytes().toString(Charsets.UTF_8) }
                } ?: throw EpubFormatException("EPUB package document is missing: $packagePath")

                val opfDir = packagePath.substringBeforeLast('/', "")

                val doc = DocumentBuilderFactory.newInstance()
                    .apply {
                        // No external entity resolution: an EPUB is untrusted input
                        // and must not be able to pull in local files or make
                        // network requests during parsing.
                        isNamespaceAware = true
                        setFeatureQuietly("http://apache.org/xml/features/disallow-doctype-decl", true)
                        setFeatureQuietly("http://xml.org/sax/features/external-general-entities", false)
                        setFeatureQuietly("http://xml.org/sax/features/external-parameter-entities", false)
                        setFeatureQuietly("http://apache.org/xml/features/nonvalidating/load-external-dtd", false)
                        isXIncludeAware = false
                        isExpandEntityReferences = false
                    }
                    .newDocumentBuilder()
                    .parse(InputSource(StringReader(opfXml)))

                val manifestById = HashMap<String, Pair<String, String>>()
                val manifestByPath = LinkedHashMap<String, String>()
                val manifestEl = doc.getElementsByTagNameNS("*", "manifest").item(0) as? Element
                if (manifestEl != null) {
                    val items = manifestEl.getElementsByTagNameNS("*", "item")
                    for (i in 0 until items.length) {
                        val item = items.item(i) as? Element ?: continue
                        val id = item.getAttribute("id")
                        val href = item.getAttribute("href")
                        val mediaType = item.getAttribute("media-type")
                        if (id.isEmpty() || href.isEmpty()) continue
                        val resolved = ArchivePath.resolve(opfDir, href) ?: continue
                        manifestById[id] = resolved to mediaType
                        manifestByPath[resolved] = mediaType
                    }
                }

                val spineHrefs = mutableListOf<String>()
                val spineEl = doc.getElementsByTagNameNS("*", "spine").item(0) as? Element
                if (spineEl != null) {
                    val itemrefs = spineEl.getElementsByTagNameNS("*", "itemref")
                    for (i in 0 until itemrefs.length) {
                        val itemref = itemrefs.item(i) as? Element ?: continue
                        if (itemref.getAttribute("linear").equals("no", ignoreCase = true)) continue
                        val idref = itemref.getAttribute("idref")
                        manifestById[idref]?.let { spineHrefs += it.first }
                    }
                }
                if (spineHrefs.isEmpty()) {
                    throw EpubFormatException("EPUB spine is empty; nothing to read")
                }

                val metadataEl = doc.getElementsByTagNameNS("*", "metadata").item(0) as? Element
                val title = metadataEl?.let { firstText(it, "title") }
                val language = metadataEl?.let { firstText(it, "language") }

                EpubPublication(zip, packagePath, title, language, spineHrefs, manifestByPath)
            } catch (t: Throwable) {
                zip.close()
                throw t
            }
        }

        private fun DocumentBuilderFactory.setFeatureQuietly(name: String, value: Boolean) {
            runCatching { setFeature(name, value) }
        }

        private fun parseContainer(xml: String): String? = runCatching {
            val doc = DocumentBuilderFactory.newInstance()
                .apply {
                    isNamespaceAware = true
                    runCatching { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
                    isExpandEntityReferences = false
                }
                .newDocumentBuilder()
                .parse(InputSource(StringReader(xml)))
            val rootfiles = doc.getElementsByTagNameNS("*", "rootfile")
            (0 until rootfiles.length)
                .mapNotNull { rootfiles.item(it) as? Element }
                .firstOrNull { it.getAttribute("media-type").contains("oebps-package", ignoreCase = true) }
                ?.getAttribute("full-path")
                ?.takeIf { it.isNotBlank() }
        }.getOrNull()

        private fun firstText(parent: Element, localName: String): String? {
            val nodes = parent.getElementsByTagNameNS("*", localName)
            for (i in 0 until nodes.length) {
                val text = nodes.item(i).textContent?.trim()
                if (!text.isNullOrEmpty()) return text
            }
            return null
        }
    }
}

class EpubFormatException(message: String) : Exception(message)
