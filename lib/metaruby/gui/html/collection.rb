module MetaRuby::GUI
    module HTML
        # Base class providing functionality to render collections of objects
        # whose rendering can be delegated
        class Collection < Qt::Object
            # @return [#push] the page on which we publish the HTML
            attr_reader :page
            # @return [RenderingManager] the object that manages the rendering
            #   objects, i.e. the objects that convert the element collections
            #   into HTML
            attr_reader :manager
            # @return [{Integer=>Object}] mapping from an element's object_id to
            #   the corresponding object
            attr_reader :object_id_to_object
            # @return [<Exception>] exceptions caught during element rendering
            attr_reader :registered_exceptions

            Element = Struct.new :object, :format, :url, :text, :rendering_options, :attributes

            def initialize(page)
                super()
                @page = page
                @manager = RenderingManager.new(page)

                @object_id_to_object = Hash.new
                @registered_exceptions = Array.new
            end
            
            def register_type(model, rendering_class, render_options = Hash.new)
                manager.register_type(model, rendering_class, render_options)
            end

            def enable
                connect(page, SIGNAL('linkClicked(const QUrl&)'), self, SLOT('linkClicked(const QUrl&)'))
                manager.enable
            end

            def disable
                disconnect(page, SIGNAL('linkClicked(const QUrl&)'), self, SLOT('linkClicked(const QUrl&)'))
                manager.disable
            end

            def clear
                @object_id_to_object.clear
                registered_exceptions.clear
                manager.clear
            end

            def namespace
                object_id.to_s + "/"
            end

            def element_link_target(object, interactive)
                if interactive
                    id =  "link://metaruby/#{namespace}#{object.object_id}"
                else
                    id =  "##{object.object_id}"
                end
            end

            def render_links(title, links, push_options = Hash.new)
                links.each do |el|
                    object_id_to_object[el.object.object_id] = el.object
                end

                links = links.map do |el|
                    a_node = el.format % ["<a href=\"#{el.url}\">#{el.text}</a>"]
                    [a_node, el.attributes || Hash.new]
                end
                page.render_list(title, links, push_options)
            end

            def render_all_elements(all, options)
                all.each do |element|
                    object_id = element.object.object_id
                    page.push(nil, "<h1 id=#{object_id}>#{element.format % element.text}</h1>")

                    render_element(element.object, options.merge(element.rendering_options))
                end
            end

            def linkClicked(url)
                if url.host == "metaruby" && url.path =~ /^\/#{Regexp.quote(namespace)}(\d+)/
                    object = object_id_to_object[Integer($1)]
                    render_element(object)
                else
                    super
                end
            end
            slots 'linkClicked(const QUrl&)'

            def render_element(object, options = Hash.new)
                page.restore
                registered_exceptions.clear
                options = Hash[id: "#{namespace}/currently_rendered_element"].merge(options)
                begin
                    manager.render(object, options)
                rescue ::Exception => e
                    registered_exceptions << e
                end
                emit updated
                page.page.current_frame.scrollToAnchor(options[:id])
            end

            signals :updated
        end
    end
end


