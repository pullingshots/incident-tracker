package IncidentTracker;
use Dancer2;
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Emailesque;

our $VERSION = '0.1';

sub set_flash { session flash => shift; session flash_type => shift || 'success' }
sub get_flash { my $msg = session('flash'); session flash => ''; return $msg; }

hook before => sub {
  if (request->path =~ m{^/cron}) {
    if (query_parameters->get('key') eq config->{cron_key}) {
      return;
    }
    forward '/';
  }

  if (query_parameters->get('continue')) {
    session sso_url => query_parameters->get('continue');
  }

  if (!session('user_id') && request->path !~ m{^/login}) {
    forward '/login';
  }
  session user => database->quick_select('users', { user_id => session('user_id') });

  if (session('sso_url') && session('user') && request->path !~ m{^/logout}) {
    use File::Slurp qw(read_file);
    use Crypt::JWT qw(encode_jwt);
    my $key = read_file('jwt.key');
    my $payload = session('user');
    $payload->{iat} = time;
    $payload->{exp} = time + (60*60*24*30);
    my $jwt = encode_jwt(payload => $payload, alg => 'RS256', key => \$key);
    my $url = session('sso_url') . "?jwt=$jwt";
    session sso_url => undef;
    redirect $url;
  }

  if (session('user') && !session('user')->{is_manager} && request->path =~ m{^/(user|add_user|unit|add_incident_unit|edit_incident)}) {
    forward '/login';
  }
};

hook before_template_render => sub {
  my $tokens = shift;
  $tokens->{'flash_msg'} = get_flash();
  $tokens->{'flash_type'} = session('flash_type');
};

hook 'database_error' => sub {
  my $error = shift;
  set_flash( $error, 'error' );
  redirect '/error';
};

get '/logout' => sub {
  session user_id => undef;
  session user => undef;
  redirect 'login';
};

get '/login' => sub {
  if (session('user')) {
    redirect '/';
  }
  template 'login';
};

post '/login' => sub {
  if (body_parameters->get('email') && body_parameters->get('login_code')) {
    my $sql = 'select validate_user( email := ?, login_code := ? )';
    my $sth = database->prepare($sql);
    $sth->execute( body_parameters->get('email'), body_parameters->get('login_code') );
    session user_id => $sth->fetch()->[0];
    if (!session('user_id')) {
      set_flash( 'Invalid code', 'error' );
      template 'login', { email => body_parameters->get('email') };
    }
    else {
      redirect '/';
    }
  }
  elsif (body_parameters->get('email')) {
    my $sql = 'select get_login_code( email := ? )';
    my $sth = database->prepare($sql);
    $sth->execute( body_parameters->get('email') );
    my $login_code = $sth->fetch()->[0];
    if ($login_code) {
      email {
        to => body_parameters->get('email'),
        subject => "Your login code: $login_code",
        message => $login_code,
      };
      template 'login', { email => body_parameters->get('email') };
    }
    else {
      set_flash( 'Invalid email', 'error' );
      template 'login';
    }
  }
  else {
    template 'login';
  }
};

get '/error' => sub {
  template 'error' => { 'title' => 'An error has occurred' };
};

get '/' => sub {
  my $managers = [ database->quick_select('users', { is_manager => 1 }, { order_by => 'name' }) ];
  my $board_members = [ database->quick_select('users', { is_board_member => 1 }, { order_by => 'name' }) ];
  template 'index' => {
    'title' => 'Maui Parkshore AOAO Issue Reporting',
    'managers' => $managers,
    'board_members' => $board_members,
  };
};

get '/users' => sub {
  template 'users' => {
    'title' => 'Users',
    'users' => [ database->quick_select('users_full', { user_type => { 'ne' => '' } }, { order_by => 'name' }) ],
  };
};

get '/users/:type' => sub {
  if (route_parameters->get('type') =~ /^(agent|owner|board_member|manager)$/) {
    template 'users' => {
      'title' => 'Users',
      'users' => [ database->quick_select('users_full', { 'is_' . route_parameters->get('type') => 1 }, { order_by => 'name' }) ],
    };
  }
  elsif (route_parameters->get('type') eq 'disabled') {
    template 'users' => {
      'title' => 'Users',
      'users' => [ database->quick_select('users_full', { is_manager => 0, is_owner => 0, is_agent => 0, is_board_member => 0 }, { order_by => 'name' }) ],
    };
  }
  else {
    redirect '/users';
  }
};

get '/add_user' => sub {
  template 'add_user' => {
    'title' => 'Add User',
  };
};

post '/add_user' => sub {
  my $sql = 'select add_user( name := ?, email := ?, phone := ?, is_owner := ?, is_agent := ?, is_manager := ?, is_board_member := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    body_parameters->get('name'),
    body_parameters->get('email'),
    body_parameters->get('phone'),
    body_parameters->get('is_owner') || 0,
    body_parameters->get('is_agent') || 0,
    body_parameters->get('is_manager') || 0,
    body_parameters->get('is_board_member') || 0
  );

  set_flash('User added!');
  redirect '/users';
};

get '/user/:user_id' => sub {
  template 'user' => {
    'title' => 'Edit User',
    'user' => database->quick_select('users', { user_id => route_parameters->get('user_id') }),
  };
};

post '/user/:user_id' => sub {
  my $sql = 'select edit_user( user_id := ?, name := ?, email := ?, phone := ?, is_owner := ?, is_agent := ?, is_manager := ?, is_board_member := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    route_parameters->get('user_id'),
    body_parameters->get('name'),
    body_parameters->get('email'),
    body_parameters->get('phone'),
    body_parameters->get('is_owner') || 0,
    body_parameters->get('is_agent') || 0,
    body_parameters->get('is_manager') || 0,
    body_parameters->get('is_board_member') || 0
  );

  set_flash('User updated!');
  redirect '/users';
};

get '/add_user_unit/:user_id' => sub {
  template 'add_user_unit' => {
    'title' => 'Add Unit to User',
    'user_id' => route_parameters->get('user_id'),
    'units' => [ database->quick_select('units_active', {}, { order_by => 'unit_number' }) ],
  };
};

post '/add_user_unit/:user_id' => sub {
  my $sql = 'select add_user_unit( user_id := ?, unit := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    route_parameters->get('user_id'),
    body_parameters->get('unit'),
  );

  if ($sth->fetch()->[0]) {
    set_flash('Unit added to user!');
  }
  else {
    set_flash('Unit was not added to user.', 'warning');
  }
  redirect '/users';
};

post '/remove_user_unit' => sub {
  my $sql = 'delete from user_unit where user_id = ? and unit_id = ?';
  my $sth = database->prepare($sql);
  my $rv = $sth->execute(
    body_parameters->get('user_id'),
    body_parameters->get('unit_id'),
  );

  if ($rv) {
    set_flash('User removed from unit!');
  }
  else {
    set_flash('User was not removed from unit.', 'warning');
  }
  redirect '/users';
};

get '/units' => sub {
  template 'units' => {
    'title' => 'Units',
    'units' => [ database->quick_select('units_full', {}, { order_by => 'unit_number' }) ],
  };
};

get '/unit/:unit_id' => sub {
  my $unit = database->quick_select('units_full', { unit_id => route_parameters->get('unit_id') });
  template 'unit' => {
    'title' => 'Unit # ' . $unit->{unit_number},
    'unit' => $unit,
  };
};

post '/unit/:unit_id' => sub {
  my $sql = 'select edit_unit( unit_id := ?, note := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    route_parameters->get('unit_id'),
    body_parameters->get('note'),
  );

  set_flash('Unit updated!');
  redirect '/units';
};

get '/incidents' => sub {
  if (defined query_parameters->get('deleted')) {
    session search_deleted => query_parameters->get('deleted');
  }
  if (defined query_parameters->get('unit')) {
    session search_unit => query_parameters->get('unit');
  }
  if (defined query_parameters->get('category')) {
    session search_category => query_parameters->get('category');
  }
  if (defined query_parameters->get('rule')) {
    session search_rule => query_parameters->get('rule');
  }
  if (defined query_parameters->get('start_date')) {
    session search_start_date => query_parameters->get('start_date');
  }
  if (defined query_parameters->get('end_date')) {
    session search_end_date => query_parameters->get('end_date');
  }

  my $where = "deleted = ? ";
  my @params = (session('search_deleted') || 'false');

  if (session('search_unit')) {
    $where .= "AND ? = ANY (units) ";
    push @params, session('search_unit');
  }
  if (session('search_category')) {
    $where .= "AND category = ? ";
    push @params, session('search_category');
  }
  if (session('search_rule')) {
    $where .= "AND rule = ? ";
    push @params, session('search_rule');
  }
  if (session('search_start_date')) {
    $where .= "AND incident_date >= ? ";
    push @params, session('search_start_date');
  }
  if (session('search_end_date')) {
    $where .= "AND incident_date <= ? ";
    push @params, session('search_end_date');
  }

  my $units;
  if (session('user')->{is_manager} || session('user')->{is_board_member}) {
    $units = [ database->quick_select('units_active', {}, { order_by => 'unit_number' }) ];
  }
  else {
    $units = [ database->quick_select('units_user', { user_id => session('user_id') }, { order_by => 'unit_number' }) ];
    if (session('search_deleted') eq 'true') {
      $where .= "AND user_id = ? ";
      push @params, session('user_id');
    }
    else {
      $where .= "AND (";
      foreach my $unit (@{$units}) {
        $where .= "? = ANY (units) OR ";
        push @params, $unit->{unit_number};
      }
      $where .= "user_id = ?) ";
      push @params, session('user_id');
    }
  }
  
  my $sql = "SELECT * FROM incidents_full WHERE $where ORDER BY incident_date desc";
debug "incidents query: $sql";
debug "query params: @params";
  my $sth = database->prepare($sql);
  $sth->execute(@params);

  template 'incidents' => {
    'title' => 'Issue Reports',
    'units' => $units,
    'categories' => [ database->quick_select('categories_active', {}, { order_by => 'category' }) ],
    'rules' => [ database->quick_select('rules_active', {}, { order_by => 'rule' }) ],
    'incidents' => $sth->fetchall_arrayref({}),
  };
};

get '/edit_incident/:incident_id' => sub {
  my $incident = database->quick_select('incidents_full', { incident_id => route_parameters->get('incident_id') });
  template 'edit_incident' => {
    'title' => 'Edit Issue',
    'incident' => $incident,
    'categories' => [ database->quick_select('categories_active', {}, { order_by => 'category' }) ],
    'rules' => [ database->quick_select('rules_active', {}, { order_by => 'rule' }) ],
  };
};

post '/edit_incident/:incident_id' => sub {
  my $sql = 'select edit_incident( incident_id := ?, incident_date := ?, category := ?, rule := ?, user_id := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    route_parameters->get('incident_id'),
    body_parameters->get('incident_date') . (body_parameters->get('incident_time') ? ' ' . body_parameters->get('incident_time') : ''),
    body_parameters->get('category'),
    body_parameters->get('rule'),
    session('user_id')
  );

  set_flash('Issue updated!');
  redirect '/incidents';
};

get '/add' => sub {
  
  template 'add' => {
    'title' => 'Add Issue Report',
    'units' => [ database->quick_select('units_active', {}, { order_by => 'unit_number' }) ],
    'categories' => [ database->quick_select('categories_active', {}, { order_by => 'category' }) ],
    'rules' => [ database->quick_select('rules_active', {}, { order_by => 'rule' }) ],
  };
};

post '/add' => sub {
  my $sql = 'select add_incident( incident_date := ?, category := ?, rule := ?, unit := ?, note := ?, user_id := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    body_parameters->get('incident_date') . (body_parameters->get('incident_time') ? ' ' . body_parameters->get('incident_time') : ''),
    body_parameters->get('category'),
    body_parameters->get('rule'),
    body_parameters->get('unit'),
    body_parameters->get('note'),
    session('user_id')
  );
  my $incident_id = $sth->fetch()->[0];

  if (session('user')->{is_manager}) {
    foreach my $in ( database->quick_select('incident_notifications', { incident_id => $incident_id }, {}) ) {
      email {
        to => $in->{email},
        subject => "New issue submitted for unit # $in->{unit_number}",
        type => "html",
        message => template 'incident_detail', {
            incident => $in,
          },
          { layout => 'email' },
      };
    }
  }
  else {
    my $in = database->quick_select('incidents_full', { incident_id => $incident_id }, {});
    foreach my $manager ( database->quick_select('users', { is_manager => 1 }, {}) ) {
      email {
        to => $manager->{email},
        subject => "New issue submitted by $in->{name}",
        type => "html",
        message => template 'incident_detail', {
            manager => 1,
            incident => $in,
          },
          { layout => 'email' },
      };
    }
  }

  set_flash('Issue report added!');
  redirect '/add';
};

post '/delete_incident/:incident_id' => sub {
  my $sql = 'select delete_incident( incident_id := ? )';
  my $sth = database->prepare($sql);
  $sth->execute( route_parameters->get('incident_id') );
  if ($sth->fetch()->[0]) {
    set_flash('Issue report marked as deleted.', 'info');
  }
  else {
    set_flash('Issue report was not marked as deleted.', 'warning');
  }
  redirect '/incidents';
};

post '/restore_incident/:incident_id' => sub {
  my $sql = 'select restore_incident( incident_id := ? )';
  my $sth = database->prepare($sql);
  $sth->execute( route_parameters->get('incident_id') );
  if ($sth->fetch()->[0]) {
    set_flash('Issue report has been restored.', 'success');
  }
  else {
    set_flash('Issue report was not restored.', 'warning');
  }
  redirect '/incidents';
};

get '/add_note/:incident_id' => sub {
  template 'add_note' => {
    'title' => 'Add Note to Issue Report',
    'incident_id' => route_parameters->get('incident_id'),
  };
};

post '/add_note/:incident_id' => sub {
  my $sql = 'select add_note( incident_id := ?, note := ?, user_id := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    route_parameters->get('incident_id'),
    body_parameters->get('note'),
    session('user_id'),
  );

  if ($sth->fetch()->[0]) {
    foreach my $in ( database->quick_select('incident_notifications', { incident_id => route_parameters->get('incident_id') }, {}) ) {
      email {
        to => $in->{email},
        subject => "New note added to issue for unit # $in->{unit_number}",
        type => "html",
        message => template 'incident_detail', {
            incident => $in,
          },
          { layout => 'email' },
      };
    }
    set_flash('Note added to issue report!');
  }
  else {
    set_flash('Note was not added to issue report.', 'warning');
  }
  redirect '/incidents';
};

get '/add_incident_unit/:incident_id' => sub {
  template 'add_incident_unit' => {
    'title' => 'Add Unit to Issue Report',
    'incident_id' => route_parameters->get('incident_id'),
    'units' => [ database->quick_select('units_active', {}, { order_by => 'unit_number' }) ],
  };
};

post '/add_incident_unit/:incident_id' => sub {
  my $sql = 'select add_incident_unit( incident_id := ?, unit := ?, user_id := ? )';
  my $sth = database->prepare($sql);
  $sth->execute(
    route_parameters->get('incident_id'),
    body_parameters->get('unit'),
    session('user_id'),
  );

  if ($sth->fetch()->[0]) {
    foreach my $in ( database->quick_select('incident_notifications', { incident_id => route_parameters->get('incident_id'), unit_number => body_parameters->get('unit') }, {}) ) {
      email {
        to => $in->{email},
        subject => "New issue submitted for unit # $in->{unit_number}",
        type => "html",
        message => template 'incident_detail', {
            incident => $in,
          },
          { layout => 'email' },
      };
    }
    set_flash('Unit added to issue report!');
  }
  else {
    set_flash('Unit was not added to issue report.', 'warning');
  }
  redirect '/incidents';
};

get 'add_photo/:incident_id' => sub {
  template 'add_photo' => {
    'title' => 'Add Photo to Issue Report',
    'incident_id' => route_parameters->get('incident_id'),
  };
};

post 'add_photo/:incident_id' => sub {
  use DBD::Pg;
  my $data = request->upload('file');

  if (!$data) {
    set_flash('Photo upload failed.', 'warning');
    redirect '/incidents';
  }
  
  my $sql = 'INSERT INTO incident_photos (incident_id, filename, content, content_type, user_id) VALUES (?, ?, ?, ?, ?)';
  my $sth = database->prepare($sql);
  $sth->bind_param( 1, route_parameters->get('incident_id') );
  $sth->bind_param( 2, $data->basename );
  $sth->bind_param( 3, $data->content, { pg_type => DBD::Pg::PG_BYTEA });
  $sth->bind_param( 4, $data->type );
  $sth->bind_param( 5, session('user_id') );
  $sth->execute();

  set_flash('Photo added to issue report!');
  redirect '/incidents';
};

get 'photo/:photo_id' => sub {
  my $photo = database->quick_select('incident_photos', { photo_id => route_parameters->get('photo_id') });
  redirect '/incidents' unless $photo;
  delayed {
    response_header 'Content-Type' => $photo->{content_type};
    response_header 'Content-Disposition' => 'inline; filename="' . $photo->{filename} . '"';
    content $photo->{content};
    done;
  };
};

get 'cron/daily' => sub {
  my $sql = "SELECT * FROM incidents_full WHERE ? = any (units) AND update_date > current_timestamp - interval '24 hours' AND deleted is false";
  my $sth = database->prepare($sql);
  foreach my $unit_owner (database->quick_select('units_user', { is_owner => 'true' }, { })) {
    $sth->execute($unit_owner->{unit_number});
    my $incidents = $sth->fetchall_arrayref({});
    if (@{$incidents}) {
      email {
        to => $unit_owner->{email},
        subject => "Daily issue summary for unit # $unit_owner->{unit_number}",
        type => "html",
        message => template 'incident_summary', {
            incidents => $incidents,
            interval => '24 hours',
          },
          { layout => 'email' },
      };
    }
  }

  $sql = "SELECT * FROM incidents_full WHERE update_date > current_timestamp - interval '24 hours' AND deleted is false";
  $sth = database->prepare($sql);
  $sth->execute();
  my $incidents = $sth->fetchall_arrayref({});
  if (@{$incidents}) {
    my $to = join ',', map { $_->{email} } database->quick_select('users', { is_board_member => 'true' }, {});
    email {
      to => $to,
      subject => "Daily issue summary",
      type => "html",
      message => template 'incident_summary', {
          incidents => $incidents,
          interval => '24 hours',
          board_member => 1,
        },
        { layout => 'email' },
    };
  }

  return;
};

true;
