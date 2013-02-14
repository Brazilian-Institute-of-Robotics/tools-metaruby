module MetaRuby
    module GUI
        # A Qt widget that allows to browse the models registered in the Ruby
        # constanat hierarchy
        class ModelSelector < Qt::Widget
            attr_reader :btn_type_filter_menu
            attr_reader :type_filters
            attr_reader :model_list
            attr_reader :model_filter
            attr_reader :type_info
            attr_reader :browser_model

            def initialize(parent = nil)
                super

                @type_info = Hash.new
                @type_filters = Hash.new

                layout = Qt::VBoxLayout.new(self)
                filter_button = Qt::PushButton.new('Filters', self)
                layout.add_widget(filter_button)
                @btn_type_filter_menu = Qt::Menu.new
                filter_button.menu = btn_type_filter_menu

                setup_tree_view(layout)
            end

            def register_type(model_base, name, priority = 0)
                type_info[model_base] = RubyConstantsItemModel::TypeInfo.new(name, priority)
                action = Qt::Action.new(name, self)
                action.checkable = true
                action.checked = true
                type_filters[model_base] = action
                btn_type_filter_menu.add_action(action)
                connect(action, SIGNAL('triggered()')) do
                    update_model_filter
                end
                update_model_filter
                reload
            end

            def update_model_filter
                rx = []
                type_filters.each do |model_base, act|
                    if act.checked?
                        rx << type_info[model_base].name
                    end
                end

                model_filter.filter_role = Qt::UserRole # filter on class/module ancestry
                model_filter.filter_reg_exp = Qt::RegExp.new(rx.join("|"))
            end


            def model?(obj)
                result = type_info.any? do |model_base, _|
                    obj.kind_of?(model_base) ||
                        (obj.kind_of?(Module) && obj <= model_base)
                end
            end

            def setup_tree_view(layout)
                @model_list = Qt::TreeView.new(self)
                @model_filter = Qt::SortFilterProxyModel.new
                model_filter.dynamic_sort_filter = true
                model_list.model = model_filter
                layout.add_widget(model_list)

                model_list.selection_model.connect(SIGNAL('currentChanged(const QModelIndex&, const QModelIndex&)')) do |index, _|
                    index = model_filter.map_to_source(index)
                    mod = browser_model.info_from_index(index)
                    if model?(mod.this)
                        emit model_selected(Qt::Variant.from_ruby(mod.this, mod.this))
                    end
                end

                reload
            end
            signals 'model_selected(QVariant)'

            def reload
                if current = current_selection
                    current_module = current.this
                    current_path = []
                    while current
                        current_path.unshift current.name
                        current = current.parent
                    end
                end

                @browser_model = RubyConstantsItemModel.new(type_info) do |mod|
                    model?(mod)
                end
                model_filter.source_model = browser_model

                if current_path && !select_by_path(*current_path)
                    select_by_module(current_module)
                end
            end

            # Selects the current model given a path in the constant names
            # This emits the model_selected signal
            #
            # @return [Boolean] true if the path resolved to something known,
            #   and false otherwise
            def select_by_path(*path)
                if index = browser_model.find_index_by_path(*path)
                    index = model_filter.map_from_source(index)
                    model_list.selection_model.set_current_index(index, Qt::ItemSelectionModel::ClearAndSelect)
                    true
                end
            end

            # Selects the given model if it registered in the model list
            # This emits the model_selected signal
            #
            # @return [Boolean] true if the path resolved to something known,
            #   and false otherwise
            def select_by_module(model)
                if index = browser_model.find_index_by_model(model)
                    index = model_filter.map_from_source(index)
                    model_list.selection_model.set_current_index(index, Qt::ItemSelectionModel::ClearAndSelect)
                    true
                end
            end

            # Returns the currently selected item
            # @return [RubyModuleModel::ModuleInfo,nil] nil if there are no
            #   selections
            def current_selection
                index = model_list.selection_model.current_index
                if index.valid?
                    index = model_filter.map_to_source(index)
                    browser_model.info_from_index(index)
                end
            end

            def object_paths
                browser_model.object_paths
            end
        end
    end
end