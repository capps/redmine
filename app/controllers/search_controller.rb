# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class SearchController < ApplicationController
  before_filter :find_optional_project

  helper :messages
  include MessagesHelper

  def index
    @object_types = Redmine::Search.available_search_types.dup
    
    # the cases are -- if submitted, then we can deduce the user's intent BUT since this controller
    # is invoked from the search index page and the "short form" elsewhere, we have to differentiate those cases
    # the index page has a scope setting, so that determines where we came from
    # Since check boxes are inferred from their absence, they require special handling
    
    if params[:submit] && params[:scope]      # we came from index page, so all params are "good"
      cookies[:s_scope] = params[:scope]
      cookies[:s_num_results] = params[:num_results]
      if params[:s_all_words].present?
        cookies[:s_all_words] = '1'
      else
        cookies.delete(:s_all_words)      
      end
      if params[:s_titles_only].present?
        cookies[:s_titles_only] = '1'
      else
        cookies.delete(:s_titles_only)
      end
      @object_types.each do |t| 
        if params[t].present?
          cookies["s_#{t}".to_sym] = '1'
        else
          cookies.delete("s_#{t}".to_sym)
        end
      end
    else
      params[:scope] = cookies[:s_scope] unless params[:scope].present?
      params[:num_results] = cookies[:s_num_results] unless params[:num_results].present?
      params[:all_words] = cookies[:s_all_words] unless params[:all_words].present?
      params[:titles_only] = cookies[:s_titles_only] unless params[:titles_only].present?
      @object_types.each do |t|
        params[t] = '1' if params[t].blank? && cookies["s_#{t}".to_sym].present?
      end
    end

    @question = params[:q] || ""
    @question.strip!
    @all_words = params[:all_words] || (params[:submit] ? false : true)
    @titles_only = !params[:titles_only].nil?
    
    projects_to_search =
      case params[:scope]
      when 'all'
        nil
      when 'my_projects'
        User.current.memberships.collect(&:project)
      when 'subprojects'
        @project ? (@project.self_and_descendants.active) : nil
      else
        @project
      end
          
    offset = nil
    begin; offset = params[:offset].to_time if params[:offset]; rescue; end
    
    # quick jump to an issue
    if @question.match(/^#?(\d+)$/) && Issue.visible.find_by_id($1.to_i)
      redirect_to :controller => "issues", :action => "show", :id => $1
      return
    end
    
    
    if projects_to_search.is_a? Project
      # don't search projects
      @object_types.delete('projects')
      # only show what the user is allowed to view
      @object_types = @object_types.select {|o| User.current.allowed_to?("view_#{o}".to_sym, projects_to_search)}
    end
      
    @scope = @object_types.select {|t| params[t]}
    @scope = @object_types if @scope.empty?
    
    # extract tokens from the question
    # eg. hello "bye bye" => ["hello", "bye bye"]
    @tokens = @question.scan(%r{((\s|^)"[\s\w]+"(\s|$)|\S+)}).collect {|m| m.first.gsub(%r{(^\s*"\s*|\s*"\s*$)}, '')}
    # tokens must be at least 2 characters long
    @tokens = @tokens.uniq.select {|w| w.length > 1 }
    
    if !@tokens.empty?
      # no more than 5 tokens to search for
      @tokens.slice! 5..-1 if @tokens.size > 5  
      
      @results = []
      @results_by_type = Hash.new {|h,k| h[k] = 0}
      
      limit = [params[:num_results].to_i, 10].max  # Guard against bigus params
      @scope.each do |s|
        r, c = s.singularize.camelcase.constantize.search(@tokens, projects_to_search,
          :all_words => @all_words,
          :titles_only => @titles_only,
          :limit => (limit+1),
          :offset => offset,
          :before => params[:previous].nil?)
        @results += r
        @results_by_type[s] += c
      end
      #if we're doing "all results" it's > 100, so group by project
      if limit > 100
        @results = @results.sort {|a,b| (a.is_a?(Project) || b.is_a?(Project) || a.is_a?(Changeset) || b.is_a?(Changeset))? b.event_datetime <=> a.event_datetime : (a.project_id != b.project_id ? a.project.name <=> b.project.name : b.event_datetime <=> a.event_datetime)}
      else
        @results = @results.sort {|a,b| b.event_datetime <=> a.event_datetime}
      end
      if params[:previous].nil?
        @pagination_previous_date = @results[0].event_datetime if offset && @results[0]
        if @results.size > limit
          @pagination_next_date = @results[limit-1].event_datetime 
          @results = @results[0, limit]
        end
      else
        @pagination_next_date = @results[-1].event_datetime if offset && @results[-1]
        if @results.size > limit
          @pagination_previous_date = @results[-(limit)].event_datetime 
          @results = @results[-(limit), limit]
        end
      end
    else
      @question = ""
    end
    render :layout => false if request.xhr?
  end

private  
  def find_optional_project
    return true unless params[:id]
    @project = Project.find(params[:id])
    check_project_privacy
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
