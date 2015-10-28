Contrainer
==========

"Controller Container" scripts used to react to other containers Docker events.

General
-------

These scripts will be on charge of performing actions whenever a container has triggered
a Docker event. The motivation is to use it as a central control point, so containers
can interact with other containers and/or with the host system.

Originally it was a requirement of having every container registering ips and names
under a central point, to be easily reachable by any other party. Eventually that became
a bigger and wider problem to solve, not only requiring a DNS-like solution, but a
central control point.

In a way is similar to a service discovery. The container running this program will
need to have access to docker.sock, so it can see what the host sees, and act accordingly
when a container emits a Docker event. Reactions will live in containers themselves,
so tt's containers solely responsability to perform any action.

How the process is
------------------

For this to be effective, the **contrainer** container should run first, so it can be
aware of others. Preferrable a contrainer per Docker Engine installed host.

What contrainer will do is the next:

  # Waiting for a container to start, by looping on Docker events.

  # Put in a list container id+event info as it happens

  # At the same time, start consuming registered events in the list

  # When reached a given container 'Create' event, all its *contrainer* scripts will be
    executed in container and output stored in **contrainer** for later execution.
    In this step, all scripts, no matter the target or event, will be executed.
    When done, start consuming that container 'inmediate' and  'Create' registered
    scripts, as returned from container previous execution. **inmediate** is like a
    internal wildcard event, used to be executed as soon as a target is available.
    More on this later, keep readin :).

  # Check all other container id + events info stored in the list, and dispatch the
    scripts

  # When reached a given container 'Die' event, first dispatch the scripts and when
    done, remove that container's list of events as created when the first time
    'Create' event was reached.

Scripts output format
---------------------

The scripts output is **really important**, as that's the only way for **contrainer** to know
a given container wants to affect other containers, **contrainer**, host itself, the
container itself or a combination of them.

This ouput will be treated as a batch, so everything inside of it will be run on the
desired target. The expected output should handle a given format, explained below:

```
<target>[:<docker event>]*[,<target>[:<docker event>]*]*
<actual commands>
...
...
```

The value for `<actual commands>` is pretty simple, they are all the commands to run.

The first line deserves some explanation:

  * **\<target\>**, indicates where to run the commands on. It's composed of keywords
    and/or container names, mixed with operators `!` and `+`. They give the chance
    to affect (or not) one or more targets, in one shot.

    So keywords are:
      * *%me*, indicates this very same container is target
      * *%contrainer*, indicates the calling **contrainer** is target
      * *%host*, indicate host is target
      * *\<container name\>*, indicate the mentioned \<container name\> is target
      * *%all*, indicate everyone is target.

    Operators helps to modify the targeted items scope, but including ones, removing
    other, etc. Think about affecting all items but host and contrainer, you'll
    use something like `%all!%host!%contrainer`. Now in case you wanna affect two
    identified targets plus the current container, you can do `name_1+name_2+%me`.
    To affect all real containers only, you can do `%all!%contrainer!%host`
    Beware of the order, this `%me!%all` will match nothing, while `%all!%me` will match
    everything but current container.

  * **<docker event>**, is the name of the event to use as triggering for the scripts
    execution. If more than one, they must be defined separated by colon (:). This is
    optional, and when no docker event is set, that means you want to trigger this
    scripts in and **inmediate** fashion (more below).

  This format can happen several times per script output, so in such case, separate
  them with commas.

  An **inmediate** event means dispatch the script inmediately, if target available,
  or schedule it for dispatch when target become available. This ones happens before
  any real Docker event.

For situation where you want to dispatch the script for the very same analyzed container,
leave the line blank. Setting it as `%me` or `!me:create` means the same as blank.

**IMPORTANT**, first line in scripts output is always treated as target and events
indicator

Super Privileged
----------------

For this to have full access to the host env (desired as this is a controller), 
it will need to be run in a **Super Privileged** state, as the container will eventually
be dispatching commands at host level (good guide about it http://developerblog.redhat.com/2014/11/06/introducing-a-super-privileged-container-concept/,
look for the section *Execute a command in the host namespace*).

**contrainer** running requirements will vary depending on the commands exposed by
other containers, but running it like the next, will work:

```
sudo docker run \
  --privileged \
  -e SYSIMAGE=/host \
  -v /:/host \
  <contrainer installed image name> \
  <contrainer command>
```

That way, all in host will be exposed into **contrainer**, so please **BE CAREFUL**
and **BE RESPONSABLE** on what the exposed scripts in your containers will do.

**contrainer** will decide how to run a given script, given the target to affect.
So, in case of containers affected, it will use the `docker exec` facility, when
**contrainer** itself is affected, it will run the commands directly and when host
is affected, the next structure will be used:

```
sudo nsenter --mount=$SYSIMAGE/proc/1/ns/mnt -- <host command>
```

That way host namespace will be accesed and the command will affect host, not container.
Depending on what you permit **contrainer** to do, you can add/drop support for
caps, as `--privileged` could be too open. In other situations you'll need to mount,
via volumes, access to certain host folders, so **contrainer** can see them clearly.
In the end , this magic is only required when you want **contrainer** to affect host.

**IMPORTANT:** **contrainer** will be able to run anything passed to it by the other containers,
good and bad thing could happen, so before running a container, ensure the scripts
offered are harmless by inspecting the container first.

Scripts in containers
---------------------

By default, scripts from other containers to be run by **contrainer** will be searched under `/contrainer/`
folder, and everything inside of it will look like this:

<pre><strong>
/contrainer/
 │
 ├── script 1
 ├── script 2
 ├── ...
 ├── ...
 └── script N
</strong></pre>

Scripts will be executed by **contrainer** and output will be used as commands to execute
on target+events as explained above, see section [Scripts Output Format](#scripts-output-format).

**contrainer** will use a list to control all these scripts existencies and dispatch
executions.


Ubuntu PPA
==========

You can find the package as a PPA here https://launchpad.net/~dalguete/+archive/ubuntu/contrainer

Sidenote: About My Experience Creating Deb Packages Plus Ubuntu's PPA
---------------------------------------------------------------------

http://dalguete.github.io/#about-my-experiences-creating-deb-packages-plus-ubuntus-ppa

