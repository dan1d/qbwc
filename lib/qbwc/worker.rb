module QBWC
  class Worker

    def requests(job, user = nil)
      []
    end

    def should_run?(job)
      true
    end

    def handle_response(response, job, request, data)
    end

  end
end
