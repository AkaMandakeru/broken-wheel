# frozen_string_literal: true

module Api
  # Every success body is `{ "data": … }`, with `"meta"` beside it on lists.
  module Rendering
    private

    def render_resource(resource_class, object, status: :ok, **params)
      render json: { data: resource_class.new(object, params: resource_params.merge(params)).serializable_hash },
             status: status
    end

    def render_collection(resource_class, objects, meta: {}, **params)
      render json: { data: resource_class.new(objects, params: resource_params.merge(params)).serializable_hash,
                     meta: meta }
    end

    def render_data(data, status: :ok, meta: nil)
      body = { data: data }
      body[:meta] = meta if meta
      render json: body, status: status
    end

    # Every resource can ask who is looking, e.g. for "is this mine?" flags.
    def resource_params
      { viewer: current_user }
    end
  end
end
