require 'redmine'
# *highly* derivative of WikiExtensionsRefIssue

module WikiExtensionsListIssue
  Redmine::WikiFormatting::Macros.register do
    desc "Displays a list of referer issues."

    #{{list_issues(-p=pnmc,-a=tris,-s=open,project,tracker,subject,status,author,assigned,created,updated)}}
    # TODO:
    #  add sort, order by stuff
    
    macro :list_issues do |obj, args|
      flgAssignee = false
      flgState=false
      flgPriority = false
      flgNoDescription = false
      flgLinkOnly = false
      flgSameProject = false
      flgReverse = false
	  # tgw
	  flgUseProjectId = false;

      # defaults
      $limit = 0
      limit_clause=''
	    $proj_id=1
      cond=''
      $state='open'


      # Search Options notation
      args.each do |arg|
        if arg=~/^\-([^\=]*)(\=.*)?$/ then
          options = $1;
          options.each_byte do |c|
            case c.chr

            when 'r'
              flgReverse = true;
            # importance == priority
            # grabbing args uses regular expression with grouping so the found thing is emitted as $1

            when 'i'
              if arg=~/^[^\=]+\=(.*)$/ then
                flgPriority = true
                $priority = $1
                # I'm sure there's a better way to do this ... sorry
                # Basically I take a space separated list of Priorities and turn it into a quoted, comma
                # separated list suitable for an SQL query
                $pri_list=''
                $priority.split(" ").each {|w| $pri_list += "'" + w + "' "}
                $pri_list.rstrip!
                $pri_list.gsub!(" ", ", ")
                #Enumeration.find_all_by_type('IssuePriority')
                x=5
              else
                raise "importance (priority) requires and argument: -i=[priority]<br>"
              end
                
            when 'l'
              # SELECT * FROM issues WHERE (project_id=28 AND assigned_to_id=31 AND status_id in (5, 6)) LIMIT 25;
              if arg=~/^[^\=]+\=(.*)$/ then
                $limit = $1
                limit_clause = ":limit => #{$limit}"
              else
                raise "limit requires and argument: -l=[limit]<br>"
              end

            when 'p'
              flgUseProjectId=true
              if arg=~/^[^\=]+\=(.*)$/ then
                $proj_id=$1;
              else
                raise "project requires an argument: -p=[project identifier]<br>"
              end

            when 'a'
              if arg=~/^[^\=]+\=(.*)$/ then
                flgAssignee = true
                $a_id = User.find_all_by_login("#{$1}").first.id
              else
                raise "assignee requires an argument: -a=[login name]<br>"
              end

            when 's'
              flgState=true
              if arg=~/^[^\=]+\=(.*)$/ then
                # open or closed
                $state=$1.downcase
              else
                raise "state requires an argument: -s=[open' | 'closed']<br>"
              end
# tgw
              else
                # change this message
              raise "unknown option:#{arg}<br>"+
                    "[options]<br>"+
                    "-i : importance (priorities as space separated list)<br>"+
                    "-l : limit<br>"+
                    "-p : project identifier<br>"+
                    "-a : assignee (login) <br>"+
                    "-s : state ('open' | 'closed')<br>"+
                    "-w=[search word]: specify search word";
            end
          end
        end
      end # args.each

    dispIssues = {};

# tgw - what's a subselect look like?
    # build select conditions
		# select * from issues where project_id in (select id from projects where identifier='pnmc');
		if flgUseProjectId then
		  proj_rec = Project.find(:all, :conditions => ["identifier='#{$proj_id}'"])
		  cond = "project_id=#{proj_rec[0].id}"
    end
    if flgAssignee then
       cond += " AND assigned_to_id=#{$a_id}"
    end
    if flgState then
      # stupid stuff to gather the IDs of Issue Status that are in the Closed/Open state
      closed_ids=[]
      closed = IssueStatus.find_by_sql ["select id from issue_statuses where is_closed = true"]
      closed.each {|y| closed_ids << y.id}

      open_ids=[]
      open = IssueStatus.find_by_sql ["select id from issue_statuses where is_closed = false"]
      open.each {|y| open_ids << y.id}
      if ($state == 'open')
        cond += " AND status_id in (#{open_ids.join(', ')})"
      end

      if ($state == 'closed')
        cond += " AND status_id in (#{closed_ids.join(', ')})"
      end
    end # flgState

    if flgPriority then
      pri_ids = []
      pri=Enumeration.find_by_sql ["select id from enumerations where name in (#{$pri_list})"]
      pri.each {|p| pri_ids << p.id}
      cond += " AND priority_id in (#{pri_ids.join(', ')})"
    end


# tgw - hack
        if ($limit !=0)
          issues = Issue.find(:all, :conditions=>cond, :limit=>$limit)
        else
          issues = Issue.find(:all, :conditions=>cond)
        end

        issues.each do |issue|
          next if !issue.visible?
          if flgLinkOnly then
            #
            refs = issue.description.scan(/\[\[(.*)\]\]/);
            refs.each do |ref|
              #
              ref = ref.shift;
              if ref=~/^(.*)\|(.*)$/ then
                #
                ref=$1;
              end
              if ref=~/^(.*)\:(.*)$/ then
                #
                refPrj=$1;
                refKeyword=$2;
              else
                #
                refPrj=issue.project.identifier;
                refKeyword=ref;
              end
              if refPrj==obj.project.identifier || refPrj==obj.project.name then
                #
                if refKeyword.downcase==searchWord.downcase then
                  #
                  dispIssues[issue.id] = issue; #
                end
              end
            end
          else
            # only wiki
            dispIssues[issue.id] = issue; #
          end
        end # do issue

      #
      disp = '<table>';
      #
      disp << '<tr><th>No.</th>';
      args.each do |column|
        #
        if column=~/^[^-]/ then
          disp << "<th>#{column}</th>";
        end
      end
      disp << '</tr>';

      #
      if flgReverse then
        dispLine = dispIssues.sort_by{|k,v| -k};
      else
        dispLine = dispIssues.sort;
      end
      dispLine.each do |key, issue|
        disp << '<tr>';
        #
        disp << '<td>';
        disp << link_to("##{issue.id}",
                        {:controller => "issues", :action => "show", :id => issue},:class => issue.css_classes
                       );
        disp << '</td>';
        #
        args.each do |column|
          column.strip!;
          case column
          when 'project'
            disp << '<td>' << issue.project.name << '</td>';
          when 'tracker'
              disp << '<td>' << issue.tracker.name << '</td>';
          when 'subject'
            disp << '<td>';
            disp << link_to("#{issue.subject}",
                            {:controller => "issues", :action => "show", :id => issue},:class => issue.css_classes
                           );
            disp << '</td>';
          when 'status'
            disp << '<td>' << issue.status.name << '</td>';
          when 'priority'
            disp << '<td>' << Enumeration.find(issue.priority).name << '</td>';
          when 'author'
            disp << '<td>';
            disp << link_to_user(issue.author) if issue.author;
            disp << '</td>';
          when 'assigned_to', 'assigned'
            disp << '<td>';
            disp << link_to_user(issue.assigned_to) if issue.assigned_to;
            disp << '</td>';
          when 'created_on', 'created'
            disp << '<td>' << format_date(issue.created_on).to_s << '</td>';
          when 'updated_on', 'updated'
            disp << '<td>' << format_date(issue.updated_on).to_s << '</td>';
          else
            if column=~/^[^-]/ then
              raise "unknown column:#{column}<br>";
            end
          end
        end
        disp << "</tr>";
      end
      disp << '</table>';
      return disp;
    end # macro :list_issues

    args=nil
  end # Macro.register

end  # end module
