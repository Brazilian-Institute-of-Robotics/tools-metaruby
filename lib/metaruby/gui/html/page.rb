module MetaRuby::GUI
    module HTML
        RESSOURCES_DIR = File.expand_path(File.dirname(__FILE__))

        # A class that can be used as the webpage container for the Page class
        class HTMLPage
            attr_accessor :html

            def main_frame; self end
        end

        # A helper class that gives us easy-to-use page elements on a
        # Qt::WebView
        class Page < Qt::Object
            attr_reader :fragments
            attr_reader :view
            attr_accessor :object_uris
            attr_reader :javascript

            class Fragment
                attr_accessor :title
                attr_accessor :html
                attr_accessor :id
                attr_reader :buttons

                def initialize(title, html, view_options = Hash.new)
                    view_options = Kernel.validate_options view_options,
                        :id => nil, :buttons => []
                    @title = title
                    @html = html
                    @id = view_options[:id]
                    @buttons = view_options[:buttons]
                end
            end

            def load_javascript(file)
                javascript << File.expand_path(file)
            end

            def link_to(object, text = nil, args = Hash.new)
                text = HTML.escape_html(text || object.name || "<anonymous>")
                if uri = uri_for(object)
                    if uri !~ /^\w+:\/\//
                        if uri[0, 1] != '/'
                            uri = "/#{uri}"
                        end
                        uri = Qt::Url.new("link://metaruby#{uri}")
                    else
                        uri = Qt::Url.new(uri)
                    end
                    args.each { |k, v| uri.add_query_item(k.to_s, v.to_s) }
                    "<a href=\"#{uri.to_string}\">#{text}</a>"
                else text
                end
            end

            # Converts the given text from markdown to HTML and generates the
            # necessary <div> context.
            #
            # @return [String] the HTML snippet that should be used to render
            #   the given text as main documentation
            def self.main_doc(text)
                "<div class=\"doc-main\">#{Kramdown::Document.new(text).to_html}</div>"
            end

            def main_doc(text)
                self.class.main_doc(text)
            end

            PAGE_TEMPLATE = File.join(RESSOURCES_DIR, "page.rhtml")
            PAGE_BODY_TEMPLATE = File.join(RESSOURCES_DIR, "page_body.rhtml")
            FRAGMENT_TEMPLATE  = File.join(RESSOURCES_DIR, "fragment.rhtml")
            LIST_TEMPLATE = File.join(RESSOURCES_DIR, "list.rhtml")
            ASSETS = %w{page.css jquery.min.js jquery.selectfilter.js}

            def self.copy_assets_to(target_dir, assets = ASSETS)
                FileUtils.mkdir_p target_dir
                assets.each do |file|
                    FileUtils.cp File.join(RESSOURCES_DIR, file), target_dir
                end
            end

            def load_template(*path)
                path = File.join(*path)
                @templates[path] ||= ERB.new(File.read(path))
                @templates[path].filename = path
                @templates[path]
            end

            attr_reader :page

            attr_accessor :page_name
            attr_accessor :title

            def initialize(page)
                super()
                @page = page
                @fragments = []
                @templates = Hash.new
                @auto_id = 0
                @javascript = Array.new

                if page.kind_of?(Qt::WebPage)
                    page.link_delegation_policy = Qt::WebPage::DelegateAllLinks
                    Qt::Object.connect(page, SIGNAL('linkClicked(const QUrl&)'), self, SLOT('pageLinkClicked(const QUrl&)'))
                end
                @object_uris = Hash.new
            end


            def uri_for(object)
                if object.kind_of?(Pathname)
                    "file://#{object.expand_path}"
                else
                    object_uris[object]
                end
            end

            # Removes all existing displays
            def clear
                page.main_frame.html = ""
                fragments.clear
            end

            def scale_attribute(node, name, scale)
                node.attributes[name] = node.attributes[name].gsub /[\d\.]+/ do |n|
                    (Float(n) * scale).to_s
                end
            end

            def update_html
                page.main_frame.html = html
            end

            def html(ressource_dir: RESSOURCES_DIR)
                load_template(PAGE_TEMPLATE).result(binding)
            end

            def html_body(ressource_dir: RESSOURCES_DIR)
                load_template(PAGE_BODY_TEMPLATE).result(binding)
            end

            def html_fragment(fragment, ressource_dir: RESSOURCES_DIR)
                load_template(FRAGMENT_TEMPLATE).result(binding)
            end

            def find_button_by_url(url)
                id = url.path
                fragments.each do |fragment|
                    if result = fragment.buttons.find { |b| b.id == id }
                        return result
                    end
                end
                nil
            end

            def find_first_element(selector)
                page.main_frame.find_first_element(selector)
            end

            def pageLinkClicked(url)
                if url.scheme == 'btn' && url.host == 'metaruby'
                    if btn = find_button_by_url(url)
                        new_state = if url.fragment == 'on' then true
                                    else false
                                    end

                        btn.state = new_state
                        new_text = btn.text
                        element = find_first_element("a##{btn.html_id}")
                        element.replace(btn.render)

                        emit buttonClicked(btn.id, new_state)
                    else
                        MetaRuby.warn "invalid button URI #{url.to_string}: could not find corresponding handler (known buttons are #{fragments.flat_map { |f| f.buttons.map { |btn| btn.id.to_string } }.sort.join(", ")})"
                    end
                elsif url.scheme == 'link' && url.host == 'metaruby'
                    emit linkClicked(url)
                elsif url.scheme == "file"
                    emit fileOpenClicked(url)
                else
                    MetaRuby.warn "MetaRuby::GUI::HTML::Page: ignored link #{url.toString}"
                end
            end
            slots 'pageLinkClicked(const QUrl&)'
            signals 'linkClicked(const QUrl&)', 'buttonClicked(const QString&,bool)', 'fileOpenClicked(const QUrl&)'

            # Save the current state of the page, so that it can be restored by
            # calling {restore}
            def save
                @saved_state = fragments.map(&:dup)
            end

            # Restore the page at the state it was at the last call to {save}
            def restore
                return if !@saved_state

                fragments_by_id = Hash.new
                @saved_state.each do |fragment|
                    fragments_by_id[fragment.id] = fragment
                end

                # Delete all fragments that are not in the saved state
                fragments.delete_if do |fragment|
                    element = find_first_element("div##{fragment.id}")
                    if old_fragment = fragments_by_id[fragment.id]
                        if old_fragment.html != fragment.html
                            element.replace(old_fragment.html)
                        end
                    else
                        element.replace("")
                        true
                    end
                end
            end

            # Adds a fragment to this page, with the given title and HTML
            # content
            #
            # The added fragment is enclosed in a div block to allow for dynamic
            # replacement
            # 
            # @option view_options [String] id the ID of the fragment. If given,
            #   and if an existing fragment with the same ID exists, the new
            #   fragment replaces the existing one, and the view is updated
            #   accordingly.
            #
            def push(title, html, view_options = Hash.new)
                if id = view_options[:id]
                    # Check whether we should replace the existing content or
                    # push it new
                    fragment = fragments.find do |fragment|
                        fragment.id == id
                    end
                    if fragment
                        fragment.html = html
                        element = find_first_element("div##{fragment.id}")
                        element.replace(html_fragment(fragment))
                        return
                    end
                end

                fragments << Fragment.new(title, html, Hash[:id => auto_id].merge(view_options))
                update_html
            end

            def auto_id
                "metaruby-html-page-fragment-#{@auto_id += 1}"
            end

            # Create an item for the rendering in tables
            def render_item(name, value = nil)
                if value
                    "<li><b>#{name}</b>: #{value}</li>"
                else
                    "<li>#{name}</li>"
                end
            end

            # Render a list of objects into HTML and push it to this page
            #
            # @param [String,nil] title the section's title. If nil, no new
            #   section is created
            # @param [Array<Object>,Array<(Object,Hash)>] items the list
            #   items, one item per line. If a hash is provided, it is used as
            #   HTML attributes for the lines
            # @param [Hash] options
            # @option options [Boolean] filter (false) if true, a filter is
            #   added at the top of the page. You must provide a :id option for
            #   the list for this to work
            # @option (see #push)
            def render_list(title, items, options = Hash.new)
                options, push_options = Kernel.filter_options options, :filter => false, :id => nil
                if options[:filter] && !options[:id]
                    raise ArgumentError, ":filter is true, but no :id has been given"
                end
                html = load_template(LIST_TEMPLATE).result(binding)
                push(title, html, push_options.merge(:id => options[:id]))
            end

            signals 'updated()'

            def self.to_html_page(object, renderer, options = Hash.new)
                webpage = HTMLPage.new
                page = new(webpage)
                renderer.new(page).render(object, options)
                page
            end

            # Renders an object to HTML using a given rendering class
            def self.to_html(object, renderer, options = Hash.new)
                html_options, options = Kernel.filter_options options, :ressource_dir => RESSOURCES_DIR
                to_html_page(object, renderer, options).html(html_options)
            end

            def self.to_html_body(object, renderer, options = Hash.new)
                html_options, options = Kernel.filter_options options, :ressource_dir => RESSOURCES_DIR
                to_html_page(object, renderer, options).html_body(html_options)
            end
        end
    end
end

