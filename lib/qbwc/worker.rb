module QBWC
  class Worker

    def requests(job, user = nil)
      []
    end

    def should_run?(job, user = nil)
      true
    end

    def handle_response(response, job, request, data, user = nil)
    end

  end
end
