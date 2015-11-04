Contrainer
==========

"**Contr**oller Cont**ainer**" scripts used to react to other containers Docker events.

Meant to be used inside a container, under Docker.

General
-------

These scripts will be on charge of performing actions whenever a container has triggered
a Docker event. The motivation is to use it as a central control point, so containers
can interact with other containers and/or with the host system, without having to
install anything on host machine.

Originally it was a requirement of having every container registering ips and names
under a central point, to be easily reachable by any other party. Eventually that became
a bigger and wider problem to solve, not only requiring a DNS-like solution, but a
central control point.

In a way is similar to a service discovery. The container running this program will
need to have access to docker.sock, so it can see what the host sees, and act accordingly
when a container emits a Docker event. Reactions will live in containers themselves,
so it's containers solely responsability to perform any action.


How the process is
------------------

For this to be effective, the **contrainer** container should run first, so it can be
aware of others. Preferrable a **contrainer** per Docker Engine installed host.

What **contrainer** will do is the next:

  1. Consume all Docker events as they get generated.

  2. Wait until a given container is completely up and running, that is after 'Start'
    event has been triggered.

  3. Gather all scripts made available by the container, now running, and register
    them for later execution. Some index scripts are created in the process, those
    used to help in the process of running the definitive scripts in the appropriate
    places.

  4. Start processing all registered scripts as soon as the Docker events are being
    triggered. There's an intenal event handled, called **_inmediate**, that can
    be used to trigger processes as soon as a container is available.
    More on this later, keep reading. :)

  3. Check all other container id + events info stored in the list, and dispatch the
    scripts.

  4. When reached a given container 'Die' event, first, dispatch the scripts and when
    done, remove that container's list of scripts registered when the first time
    'Start' event, was reached.


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

The value for `<actual commands>` is straightforward, they are all the commands to run.

The first line, know as **header** deserves some explanation:

  * **\<target\>**, indicates where to run the commands into. It's composed of keywords
    and/or container names, mixed with operators `~` and `+`. They give the chance
    to affect (or not) one or more targets, in one shot.

    So keywords are:
      * **%me**, indicates this very same container is the target.
      * **%contrainer**, indicates the calling **contrainer** is the target.
      * **%host**, indicate host is the target.
      * **\<container name\>**, indicate the mentioned \<container name\> is the target.
      * **%all**, indicate everyone is the target.

    Operators helps to modify the targeted items scope, by including ones, removing
    others, etc.

    Think about this; affect all items but host and contrainer, you'll use something like:
    ```
    %all~%host~%contrainer
    ```

    Now in case you wanna affect two identified targets plus the current container,
    you can use:
    ```
    name_1+name_2+%me
    ```

    To affect all real containers only, you can use:
    ```
    %all~%contrainer~%host
    ```

    Beware of the order, this **`%me~%all`** will match nothing (no targets), while
    **`%all~%me`** will match everything but current container.

  * **\<docker event\>**, is the name of the event (all lowercase) to use as trigger, for the scripts
    execution. If more than one, they must be defined separated by colon (:). This is
    optional, and when no docker event is set, that means you want to trigger the
    script in and **_inmediate** fashion (more below).

This format can happen several times per script output, so in such cases, separate
them with commas, something like:
    ```
    %all~%host~%contrainer,name_1+name_2+%me:create:destroy
    ```

An **_inmediate** event means dispatch the script inmediately, if target available,
or schedule it for dispatch when target becomes available. This ones happens before
any real Docker event.

For situations where you want to dispatch the script for the very same analyzed container,
it's better to leave the line blank.
Setting it as `%me`, will give you same results.

You'd think `%me:create` means the same, but that's not completely true, as those
scripts will be run only when container has reached the 'Create' Docker event. If
the container was already working (already created) when this new entry was added,
scripts with that header will not be run.

For improved readability, spaces are allowed anywhere. When processed they will be
simply removed.

Super Privileged
----------------

For **contrainer** to have full access to the host env (desired as this is a controller), 
it will need to be run in a **Super Privileged** state, as the container will be eventually
dispatching commands at host level (good guide about it http://developerblog.redhat.com/2014/11/06/introducing-a-super-privileged-container-concept/,
look for the section *Execute a command in the host namespace*), and mainly, to
let **contrainer** to use Docker commands direclty, inside of it, like if Docker
was installed (More info on that, http://jpetazzo.github.io/2015/09/03/do-not-use-docker-in-docker-for-ci/)

**contrainer** running settings will vary depending on the commands exposed by
other containers, but running it like the next, will work:

```
sudo docker run \
  --privileged \
  -e SYSIMAGE=/host \
  -v /:/host \
  <contrainer installed image name> \
  <contrainer command>
```

(Inner processes expect to use **SYSIMAGE** env var, so always set it).

That way, everything in host will be exposed into **contrainer**, so please **BE CAREFUL**
and **BE RESPONSABLE** on what the exposed scripts, in your containers, will do.

**contrainer** will decide how to run a given script, given the target to affect.
So, when containers are targets, it will use the `docker exec` facility, when
**contrainer** itself is affected, it will run the commands directly in command
line and when host is affected, the next structure will be used:

```
sudo nsenter --mount=$S1YSIMAGE/proc/1/ns/mnt -- <host command>
```

That way host namespace will be accesed and the command will affect host, not **contrainer**.
Depending on what you permit **contrainer** to do, you can add/drop support for
caps, as `--privileged` could be too open. In other situations you'll need to mount,
via volumes, access to certain host folders, so **contrainer** can see them clearly.

The most complicated params to run **contrainer**, the more diverse and complicated
operations container scripts will be able to perform; but also the most the responsibility
on your shoulders to not see your host die.

<strong>IMPORTANT: <em>contrainer</em> will be able to run anything passed to it by the other containers,
good and bad things can happen, so before running a container, aimed to be controlled
by <em>contrainer</em>, ensure the scripts offered are harmless by inspecting the
container first.</strong>

Scripts in containers
---------------------

By default, **contrainer** will search for scripts to run (in other containers) under `/contrainer/`
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

As explained before, scripts will be executed by **contrainer**, and output will
be used as commands to execute on *target+events* as explained above, see section
[Scripts Output Format](#scripts-output-format).

**contrainer** will use a list to control all these scripts existences and dispatch
executions.


Contrainer Dockerfile
---------------------

There's an automatically build image that holds all the **contrainer** functionality
in case you don't want to install it manually. It's here https://github.com/dalguete/contrainer-docker.git


Ubuntu PPA
==========

You can find the package as a PPA here https://launchpad.net/~dalguete/+archive/ubuntu/contrainer

Sidenote: About My Experience Creating Deb Packages Plus Ubuntu's PPA
---------------------------------------------------------------------

http://dalguete.github.io/#about-my-experiences-creating-deb-packages-plus-ubuntus-ppa

